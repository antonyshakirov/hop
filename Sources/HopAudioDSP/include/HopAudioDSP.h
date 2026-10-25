#ifndef HOP_AUDIO_DSP_H
#define HOP_AUDIO_DSP_H
#include <AudioToolbox/AudioToolbox.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct HopAudioChannel HopAudioChannel;
HopAudioChannel *hop_audio_create(double sample_rate);
void hop_audio_destroy(HopAudioChannel *channel);
void hop_audio_configure(HopAudioChannel *channel, float gain, bool muted, bool bass);
void hop_audio_compensate_clock(HopAudioChannel *channel);
uint32_t hop_audio_push(HopAudioChannel *channel, const AudioBufferList *input, uint32_t frames);
void hop_audio_render(HopAudioChannel *channel, AudioBufferList *output, uint32_t frames, bool add);
float hop_audio_peak(HopAudioChannel *channel);
float hop_audio_source_peak(HopAudioChannel *channel);
/* Call only after stopping the playback consumer. The capture producer may run. */
void hop_audio_discard_queued(HopAudioChannel *channel);
uint32_t hop_audio_queued(HopAudioChannel *channel);
void hop_audio_set_playback_enabled(HopAudioChannel *channel, bool enabled);
bool hop_audio_playback_ready(HopAudioChannel *channel);
void hop_audio_limit(AudioBufferList *output, uint32_t frames);
#endif
