#include "HopAudioDSP.h"
#include "rnnoise.h"
#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>

#define CAPACITY 8192u
#define FRAME 480u

struct HopAudioChannel {
    float ring[CAPACITY * 2];
    atomic_uint_fast64_t write, read;
    atomic_uint flags;
    _Atomic(float) target, peak;
    float gain, smooth, b[3], a[2], z[2][2];
    DenoiseState *noise[2];
    float noise_in[2][FRAME], noise_out[2][FRAME];
    unsigned noise_index;
    bool noise_on, noise_available;
    bool drift, primed, mono;
    double fraction, rate;
};

HopAudioChannel *hop_audio_create(double rate) {
    if (!isfinite(rate) || rate < 8000 || rate > 192000) return NULL;
    HopAudioChannel *s = calloc(1, sizeof(*s));
    if (!s) return NULL;
    atomic_init(&s->write, 0); atomic_init(&s->read, 0);
    atomic_init(&s->flags, 0); atomic_init(&s->target, 1); atomic_init(&s->peak, 0);
    s->gain = 1; s->rate = 1; s->smooth = (float)(1 - exp(-1 / (rate * .005)));
    const double A = pow(10, 6.0 / 40), w = 2 * M_PI * 180 / rate;
    const double c = cos(w), alpha = sin(w) / 2 * sqrt(2), beta = 2 * sqrt(A) * alpha;
    const double a0 = (A + 1) + (A - 1) * c + beta;
    s->b[0] = A * ((A + 1) - (A - 1) * c + beta) / a0;
    s->b[1] = 2 * A * ((A - 1) - (A + 1) * c) / a0;
    s->b[2] = A * ((A + 1) - (A - 1) * c - beta) / a0;
    s->a[0] = -2 * ((A - 1) + (A + 1) * c) / a0;
    s->a[1] = ((A + 1) + (A - 1) * c - beta) / a0;
    s->noise_available = fabs(rate - 48000) < 1;
    if (s->noise_available) {
        s->noise[0] = rnnoise_create(NULL); s->noise[1] = rnnoise_create(NULL);
        if (!s->noise[0] || !s->noise[1]) { hop_audio_destroy(s); return NULL; }
    }
    return s;
}

void hop_audio_destroy(HopAudioChannel *s) {
    if (!s) return;
    for (unsigned c = 0; c < 2; ++c) if (s->noise[c]) rnnoise_destroy(s->noise[c]);
    free(s);
}

void hop_audio_compensate_clock(HopAudioChannel *s) { if (s) s->drift = true; }
void hop_audio_mono_voice(HopAudioChannel *s) { if (s) s->mono = true; }

void hop_audio_configure(HopAudioChannel *s, float gain, bool muted, bool denoise, bool bass) {
    if (!s) return;
    atomic_store_explicit(&s->target, isfinite(gain) ? fminf(2, fmaxf(0, gain)) : 1, memory_order_relaxed);
    atomic_store_explicit(&s->flags, (muted ? 1 : 0) | (denoise && s->noise_available ? 2 : 0) | (bass ? 4 : 0), memory_order_release);
}

static float sample(const AudioBufferList *abl, unsigned channel, uint32_t frame) {
    const unsigned requested = channel;
    for (unsigned b = 0; b < abl->mNumberBuffers; ++b) {
        const AudioBuffer *buffer = &abl->mBuffers[b];
        if (channel < buffer->mNumberChannels) {
            const size_t i = (size_t)frame * buffer->mNumberChannels + channel;
            if (!buffer->mData || i >= buffer->mDataByteSize / sizeof(float)) return 0;
            const float value = ((const float *)buffer->mData)[i];
            return isfinite(value) ? value : 0;
        }
        channel -= buffer->mNumberChannels;
    }
    return requested ? sample(abl, 0, frame) : 0;
}

uint32_t hop_audio_push(HopAudioChannel *s, const AudioBufferList *input, uint32_t frames) {
    if (!s || !input || !input->mNumberBuffers) return 0;
    const uint64_t write = atomic_load_explicit(&s->write, memory_order_relaxed);
    const uint64_t read = atomic_load_explicit(&s->read, memory_order_acquire);
    if (frames > CAPACITY || write - read + frames > CAPACITY) return 0;
    for (uint32_t f = 0; f < frames; ++f) {
        const unsigned index = (unsigned)((write + f) & (CAPACITY - 1)) * 2;
        s->ring[index] = sample(input, 0, f); s->ring[index + 1] = sample(input, 1, f);
    }
    atomic_store_explicit(&s->write, write + frames, memory_order_release);
    return frames;
}

static float limit(float value) {
    const float magnitude = fabsf(value);
    if (!isfinite(value)) return 0;
    return magnitude <= .9f ? value : copysignf(.9f + .1f * tanhf((magnitude - .9f) * 10), value);
}

static void store(AudioBufferList *abl, uint32_t frame, const float values[2], bool add) {
    unsigned channel = 0, total = 0;
    for (unsigned b = 0; b < abl->mNumberBuffers; ++b) total += abl->mBuffers[b].mNumberChannels;
    for (unsigned b = 0; b < abl->mNumberBuffers; ++b) {
        AudioBuffer *buffer = &abl->mBuffers[b];
        if (!buffer->mData) { channel += buffer->mNumberChannels; continue; }
        for (unsigned c = 0; c < buffer->mNumberChannels; ++c, ++channel) {
            const size_t i = (size_t)frame * buffer->mNumberChannels + c;
            if (i >= buffer->mDataByteSize / sizeof(float)) continue;
            const float value = total == 1 ? (values[0] + values[1]) * .5f : channel < 2 ? values[channel] : 0;
            if (add) ((float *)buffer->mData)[i] += value; else ((float *)buffer->mData)[i] = value;
        }
    }
}

void hop_audio_render(HopAudioChannel *s, AudioBufferList *output, uint32_t frames, bool add) {
    if (!s || !output) return;
    const unsigned flags = atomic_load_explicit(&s->flags, memory_order_acquire);
    const float target = flags & 1 ? 0 : atomic_load_explicit(&s->target, memory_order_relaxed);
    const bool noise = flags & 2;
    if (noise != s->noise_on) {
        s->noise_on = noise; s->noise_index = 0;
        for (unsigned c = 0; c < 2; ++c) for (unsigned i = 0; i < FRAME; ++i) s->noise_out[c][i] = 0;
    }
    uint64_t read = atomic_load_explicit(&s->read, memory_order_relaxed);
    const uint64_t write = atomic_load_explicit(&s->write, memory_order_acquire);
    if (s->drift && !s->primed && write - read >= 1024 + frames) s->primed = true;
    if (s->drift && s->primed) {
        const double error = (double)(write - read) - (1024 + frames);
        const double target_rate = 1 + fmax(-.01, fmin(.01, error * .00001));
        s->rate += .02 * (target_rate - s->rate);
    }
    float peak = 0;
    for (uint32_t f = 0; f < frames; ++f) {
        float values[2] = {0, 0};
        if (read < write && (!s->drift || s->primed)) {
            const unsigned index = (unsigned)(read & (CAPACITY - 1)) * 2;
            values[0] = s->ring[index]; values[1] = s->ring[index + 1];
            if (s->drift) {
                if (read + 1 < write) {
                    const unsigned next = (unsigned)((read + 1) & (CAPACITY - 1)) * 2;
                    for (unsigned c = 0; c < 2; ++c) values[c] += (s->ring[next + c] - values[c]) * (float)s->fraction;
                }
                s->fraction += s->rate;
                const uint64_t step = (uint64_t)s->fraction;
                read += step; s->fraction -= step;
                if (read >= write) { read = write; s->fraction = 0; }
            } else ++read;
        }
        s->gain += (target - s->gain) * s->smooth;
        for (unsigned c = 0; c < 2; ++c) {
            if (noise) {
                s->noise_in[c][s->noise_index] = values[c] * 32768;
                values[c] = s->noise_out[c][s->noise_index] / 32768;
            }
            if (flags & 4) {
                const float filtered = s->b[0] * values[c] + s->z[c][0];
                s->z[c][0] = s->b[1] * values[c] - s->a[0] * filtered + s->z[c][1];
                s->z[c][1] = s->b[2] * values[c] - s->a[1] * filtered;
                values[c] = filtered;
            }
            values[c] = limit(values[c] * s->gain);
            if (flags & 1) values[c] = 0;
            peak = fmaxf(peak, fabsf(values[c]));
        }
        if (noise && ++s->noise_index == FRAME) {
            rnnoise_process_frame(s->noise[0], s->noise_out[0], s->noise_in[0]);
            if (!s->mono) rnnoise_process_frame(s->noise[1], s->noise_out[1], s->noise_in[1]);
            else for (unsigned i = 0; i < FRAME; ++i) s->noise_out[1][i] = s->noise_out[0][i];
            s->noise_index = 0;
        }
        store(output, f, values, add);
    }
    atomic_store_explicit(&s->read, read, memory_order_release);
    atomic_store_explicit(&s->peak, peak, memory_order_relaxed);
}

float hop_audio_peak(HopAudioChannel *s) { return s ? atomic_load_explicit(&s->peak, memory_order_relaxed) : 0; }
uint32_t hop_audio_queued(HopAudioChannel *s) {
    if (!s) return 0;
    const uint64_t read = atomic_load_explicit(&s->read, memory_order_acquire);
    const uint64_t write = atomic_load_explicit(&s->write, memory_order_acquire);
    return (uint32_t)(write - read);
}

void hop_audio_limit(AudioBufferList *output, uint32_t frames) {
    if (!output) return;
    for (unsigned b = 0; b < output->mNumberBuffers; ++b) {
        AudioBuffer *buffer = &output->mBuffers[b];
        if (!buffer->mData) continue;
        const size_t count = fmin((size_t)frames * buffer->mNumberChannels, buffer->mDataByteSize / sizeof(float));
        float *values = buffer->mData;
        for (size_t i = 0; i < count; ++i) values[i] = limit(values[i]);
    }
}
