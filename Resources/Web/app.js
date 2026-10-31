'use strict';

const STATUS_LABELS = {
  working: 'Working…',
  needsInput: 'Needs your approval',
  finished: 'Your turn',
  idle: 'Idle',
  closed: 'Not running'
};

const TOKEN_PATTERN = /^[A-Za-z0-9_-]{16,128}$/;
const SESSION_PATTERN = /^[A-Za-z0-9._-]{1,128}$/;

const state = {
  token: null,
  sessions: [],
  current: null,
  stream: null,
  loadingMessages: false
};

function $(id) {
  return document.getElementById(id);
}

function element(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  return node;
}

function readStoredToken() {
  try {
    return localStorage.getItem('token');
  } catch (_) {
    return null;
  }
}

function storeToken(token) {
  try {
    if (token) localStorage.setItem('token', token);
    else localStorage.removeItem('token');
  } catch (_) {
    return;
  }
}

function tokenFrom(text) {
  const value = String(text || '').trim();
  const index = value.indexOf('#');
  const fragment = index >= 0 ? value.slice(index + 1) : value;
  const fromParams = new URLSearchParams(fragment).get('token');
  const candidate = fromParams || fragment;
  return TOKEN_PATTERN.test(candidate) ? candidate : null;
}

function takeTokenFromLocation() {
  const params = new URLSearchParams(location.hash.slice(1));
  if (!params.has('token')) return;
  const token = tokenFrom(location.hash);
  history.replaceState(null, '', location.pathname);
  if (token) storeToken(token);
}

function authHeaders(extra) {
  return Object.assign({ Authorization: 'Bearer ' + state.token }, extra || {});
}

async function api(path, options) {
  const settings = options || {};
  const response = await fetch(path, {
    method: settings.method || 'GET',
    headers: authHeaders(settings.headers),
    body: settings.body,
    cache: 'no-store',
    credentials: 'omit',
    redirect: 'error'
  });
  if (response.status === 401 || response.status === 403) {
    unpair('This device is no longer paired. Scan a new code on your Mac.');
    throw new Error('Not paired');
  }
  let body = {};
  try {
    body = await response.json();
  } catch (_) {
    body = {};
  }
  if (!response.ok) throw new Error(typeof body.error === 'string' ? body.error : 'Request failed (' + response.status + ')');
  return body;
}

function show(view) {
  for (const id of ['pair-view', 'list-view', 'detail-view']) {
    $(id).hidden = id !== view;
  }
  $('back').hidden = view !== 'detail-view';
  if (view !== 'detail-view') $('heading').textContent = 'ThreadHaven';
}

function setOnline(online) {
  const dot = $('connection');
  dot.classList.toggle('online', online);
  dot.setAttribute('aria-label', online ? 'Connected' : 'Offline');
}

function relativeTime(iso) {
  const date = new Date(iso);
  if (isNaN(date.getTime())) return '';
  const seconds = Math.round((Date.now() - date.getTime()) / 1000);
  if (seconds < 60) return 'just now';
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return minutes + ' min ago';
  const hours = Math.round(minutes / 60);
  if (hours < 48) return hours + ' h ago';
  return Math.round(hours / 24) + ' days ago';
}

function badge(status) {
  const node = element('span', 'badge status-' + (STATUS_LABELS[status] ? status : 'idle'), STATUS_LABELS[status] || status);
  return node;
}

function renderSessions() {
  const running = $('running');
  const recent = $('recent');
  running.replaceChildren();
  recent.replaceChildren();
  for (const session of state.sessions) {
    const item = element('li');
    const button = element('button', 'session');
    button.type = 'button';
    button.appendChild(element('span', 'title', session.title));
    button.appendChild(badge(session.status));
    const meta = [session.project, relativeTime(session.lastActivity)];
    if (session.contextPercent > 0) meta.push(session.contextPercent + '% context');
    button.appendChild(element('span', 'meta', meta.filter(Boolean).join(' · ')));
    button.addEventListener('click', () => openSession(session.id));
    item.appendChild(button);
    (session.status === 'closed' ? recent : running).appendChild(item);
  }
  $('running-heading').hidden = running.children.length === 0;
  $('recent-heading').hidden = recent.children.length === 0;
  $('empty').hidden = state.sessions.length > 0;
}

function currentSession() {
  return state.sessions.find((session) => session.id === state.current) || null;
}

function renderDetailHeader() {
  const session = currentSession();
  if (!session) return;
  $('heading').textContent = session.title;
  const status = $('detail-status');
  status.className = 'badge status-' + (STATUS_LABELS[session.status] ? session.status : 'idle');
  status.textContent = STATUS_LABELS[session.status] || session.status;
  $('detail-project').textContent = session.project;
  const canSend = session.canSend === true;
  $('prompt').disabled = !canSend;
  $('send').disabled = !canSend;
  if (!canSend) $('composer-note').textContent = 'You can send prompts to chats running in Terminal or iTerm2 on your Mac.';
  else if ($('composer-note').dataset.kind !== 'error') $('composer-note').textContent = '';
}

function renderMessages(messages) {
  const list = $('messages');
  const nearBottom = window.innerHeight + window.scrollY >= document.body.scrollHeight - 80;
  list.replaceChildren();
  if (messages.length === 0) list.appendChild(element('li', 'muted center', 'No messages to show yet.'));
  for (const message of messages) {
    const role = message.role === 'user' ? 'user' : 'assistant';
    list.appendChild(element('li', 'message ' + role, String(message.text || '')));
  }
  if (nearBottom || list.dataset.session !== state.current) window.scrollTo(0, document.body.scrollHeight);
  list.dataset.session = state.current;
}

async function loadMessages() {
  const id = state.current;
  if (!id || state.loadingMessages) return;
  state.loadingMessages = true;
  try {
    const body = await api('/api/sessions/' + encodeURIComponent(id) + '/messages');
    if (state.current === id) renderMessages(Array.isArray(body.messages) ? body.messages : []);
  } catch (error) {
    if (state.current === id) setNote(error.message, true);
  } finally {
    state.loadingMessages = false;
  }
}

function setNote(text, isError) {
  const note = $('composer-note');
  note.textContent = text;
  note.dataset.kind = isError ? 'error' : '';
  note.classList.toggle('error', Boolean(isError));
}

function openSession(id) {
  if (!SESSION_PATTERN.test(id)) return;
  state.current = id;
  $('messages').replaceChildren();
  setNote('', false);
  show('detail-view');
  renderDetailHeader();
  if (location.hash !== '#session=' + encodeURIComponent(id)) history.pushState(null, '', '#session=' + encodeURIComponent(id));
  loadMessages();
}

function closeSession() {
  state.current = null;
  show('list-view');
  renderSessions();
}

function applySessions(sessions) {
  if (!Array.isArray(sessions)) return;
  const previous = currentSession();
  state.sessions = sessions.filter((session) => session && typeof session.id === 'string' && SESSION_PATTERN.test(session.id));
  renderSessions();
  const current = currentSession();
  if (current) {
    renderDetailHeader();
    if (!previous || previous.status !== current.status || previous.lastActivity !== current.lastActivity) loadMessages();
  }
}

async function refreshSessions() {
  try {
    const body = await api('/api/sessions');
    $('list-error').textContent = '';
    applySessions(body.sessions);
  } catch (error) {
    $('list-error').textContent = error.message;
  }
}

function handleEvent(chunk) {
  let name = 'message';
  const data = [];
  for (const line of chunk.split('\n')) {
    if (line.startsWith('event:')) name = line.slice(6).trim();
    else if (line.startsWith('data:')) data.push(line.slice(5).replace(/^ /, ''));
  }
  if (name !== 'sessions' || data.length === 0) return;
  try {
    applySessions(JSON.parse(data.join('\n')).sessions);
  } catch (_) {
    return;
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function listen() {
  while (state.token) {
    const controller = new AbortController();
    state.stream = controller;
    try {
      const response = await fetch('/api/events', {
        headers: authHeaders(),
        cache: 'no-store',
        credentials: 'omit',
        signal: controller.signal
      });
      if (response.status === 401 || response.status === 403) {
        unpair('This device is no longer paired. Scan a new code on your Mac.');
        return;
      }
      if (response.ok && response.body) {
        setOnline(true);
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let buffer = '';
        for (;;) {
          const part = await reader.read();
          if (part.done) break;
          buffer += decoder.decode(part.value, { stream: true }).replace(/\r\n/g, '\n');
          if (buffer.length > 1000000) break;
          let index = buffer.indexOf('\n\n');
          while (index >= 0) {
            handleEvent(buffer.slice(0, index));
            buffer = buffer.slice(index + 2);
            index = buffer.indexOf('\n\n');
          }
        }
      }
    } catch (_) {
      setOnline(false);
    }
    setOnline(false);
    if (!state.token) return;
    await sleep(5000);
  }
}

function base64UrlToBytes(text) {
  const padded = text.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((text.length + 3) % 4);
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function sameBytes(buffer, bytes) {
  if (!buffer) return false;
  const view = new Uint8Array(buffer);
  if (view.length !== bytes.length) return false;
  return view.every((value, index) => value === bytes[index]);
}

function pushSupported() {
  return 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
}

async function enableNotifications() {
  const status = $('notify-state');
  try {
    const permission = await Notification.requestPermission();
    if (permission !== 'granted') {
      status.textContent = 'Notifications are blocked for this page.';
      return;
    }
    const registration = await navigator.serviceWorker.ready;
    const body = await api('/api/push/key');
    const key = base64UrlToBytes(body.key);
    let subscription = await registration.pushManager.getSubscription();
    if (subscription && !sameBytes(subscription.options.applicationServerKey, key)) {
      await subscription.unsubscribe();
      subscription = null;
    }
    if (!subscription) {
      subscription = await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: key });
    }
    await api('/api/push/subscribe', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(subscription.toJSON())
    });
    status.textContent = 'Notifications are on.';
    $('notify').hidden = true;
  } catch (error) {
    status.textContent = 'Could not turn on notifications: ' + error.message;
  }
}

function updateNotifyButton() {
  const button = $('notify');
  const status = $('notify-state');
  if (!pushSupported()) {
    button.hidden = true;
    const standalone = window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
    status.textContent = standalone ? '' : 'Add this page to your home screen to get notifications.';
    return;
  }
  button.hidden = Notification.permission === 'granted' && status.textContent === 'Notifications are on.';
}

async function sendPrompt(event) {
  event.preventDefault();
  const session = currentSession();
  const field = $('prompt');
  const text = field.value.trim();
  if (!session || !text) return;
  $('send').disabled = true;
  setNote('Sending…', false);
  try {
    await api('/api/sessions/' + encodeURIComponent(session.id) + '/prompt', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text })
    });
    field.value = '';
    setNote('Sent.', false);
    setTimeout(loadMessages, 1500);
  } catch (error) {
    setNote(error.message, true);
  } finally {
    renderDetailHeader();
  }
}

function unpair(message) {
  storeToken(null);
  state.token = null;
  state.sessions = [];
  state.current = null;
  if (state.stream) state.stream.abort();
  setOnline(false);
  $('pair-message').textContent = message || '';
  show('pair-view');
}

function pairFromForm(event) {
  event.preventDefault();
  const token = tokenFrom($('pair-input').value);
  if (!token) {
    $('pair-message').textContent = 'That does not look like a pairing link from ThreadHaven.';
    return;
  }
  $('pair-input').value = '';
  storeToken(token);
  start();
}

function routeFromLocation() {
  const params = new URLSearchParams(location.hash.slice(1));
  const id = params.get('session');
  if (id && SESSION_PATTERN.test(id)) openSession(id);
  else if (state.current) closeSession();
}

function start() {
  state.token = readStoredToken();
  if (!state.token || !TOKEN_PATTERN.test(state.token)) {
    show('pair-view');
    return;
  }
  $('pair-message').textContent = '';
  show('list-view');
  updateNotifyButton();
  refreshSessions().then(routeFromLocation);
  listen();
}

document.addEventListener('DOMContentLoaded', () => {
  takeTokenFromLocation();
  $('pair-form').addEventListener('submit', pairFromForm);
  $('composer').addEventListener('submit', sendPrompt);
  $('back').addEventListener('click', () => {
    if (location.hash) history.pushState(null, '', location.pathname);
    closeSession();
  });
  $('notify').addEventListener('click', enableNotifications);
  $('sign-out').addEventListener('click', () => unpair(''));
  $('prompt').addEventListener('keydown', (event) => {
    if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) sendPrompt(event);
  });
  window.addEventListener('popstate', routeFromLocation);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible' && state.token) {
      refreshSessions();
      if (state.current) loadMessages();
    }
  });
  if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('/sw.js', { scope: '/' }).catch(() => undefined);
    navigator.serviceWorker.addEventListener('message', (event) => {
      const id = event.data && event.data.session;
      if (typeof id === 'string' && SESSION_PATTERN.test(id) && state.token) openSession(id);
    });
  }
  start();
});
