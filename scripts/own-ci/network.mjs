import net from 'node:net'
import http from 'node:http'
import https from 'node:https'
import tls from 'node:tls'
import childProcess from 'node:child_process'
import { syncBuiltinESMExports } from 'node:module'

const hosts = new Set(['localhost', '127.0.0.1', '::1', '[::1]'])
function check(host) {
  if (!hosts.has(String(host))) throw new Error('LOCAL_RELEASE_EXTERNAL_NETWORK_BLOCKED')
}
function checkRequest(value) {
  if (typeof value === 'string' || value instanceof URL) check(new URL(value).hostname)
  else check(value?.hostname ?? value?.host ?? 'localhost')
}
const connect = net.Socket.prototype.connect
net.Socket.prototype.connect = function (...args) {
  const options = Array.isArray(args[0]) ? args[0][0] : args[0]
  if (options && typeof options === 'object' && !options.path) check(options.host ?? 'localhost')
  else if (typeof options === 'number') check(typeof args[1] === 'string' ? args[1] : 'localhost')
  return connect.apply(this, args)
}
for (const protocol of [http, https]) {
  for (const key of ['request', 'get']) {
    const original = protocol[key]
    protocol[key] = function (...args) { checkRequest(args[0]); return original.apply(this, args) }
  }
}
const tlsConnect = tls.connect
tls.connect = function (...args) {
  if (typeof args[0] === 'object') check(args[0].host ?? 'localhost')
  else check(typeof args[1] === 'string' ? args[1] : 'localhost')
  return tlsConnect.apply(this, args)
}
const originalFetch = globalThis.fetch
globalThis.fetch = async function (value, ...args) {
  const target = typeof value === 'object' && value?.url ? value.url : value
  if (!(args[0]?.dispatcher && new URL(target).hostname === 'provider.test')) checkRequest(target)
  return originalFetch.call(this, value, ...args)
}
const preload = `--import ${import.meta.url}`
function guarded(options) {
  const env = { ...(options?.env ?? process.env) }
  if (!(env.NODE_OPTIONS ?? '').includes(import.meta.url)) env.NODE_OPTIONS = `${env.NODE_OPTIONS ?? ''} ${preload}`.trim()
  return { ...options, env }
}
for (const key of ['spawn', 'spawnSync', 'fork']) {
  const original = childProcess[key]
  childProcess[key] = function (command, args, options) {
    return Array.isArray(args) ? original.call(this, command, args, guarded(options)) : original.call(this, command, guarded(args))
  }
}
if (!(process.env.NODE_OPTIONS ?? '').includes(import.meta.url)) process.env.NODE_OPTIONS = `${process.env.NODE_OPTIONS ?? ''} ${preload}`.trim()
syncBuiltinESMExports()
