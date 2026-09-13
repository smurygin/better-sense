# -*- coding: utf-8 -*-
"""Per-application SWF lifecycle and cooperative settings hooks for client 1.45.

No settings are persisted here. All calls retain the client's original model and
its Apply/OK/Cancel behavior. Compatible with CPython 2.7 and 3 for local tests.
"""

from functools import wraps
import logging
import re
import weakref

_log = logging.getLogger('better_sense')
VIEW_ALIAS = 'BETTER_SENSE_HELPER'
LOAD_TIMEOUT_SECONDS = 2.0
_VERSION = re.compile(r'^\s*(?:v\.?)?1\.45(?:\.[0-9]+){0,2}\s*(?:#\s*[0-9]+)?\s*$')


def is_supported_version(version):
    return isinstance(version, (type(''), type(u''))) and _VERSION.match(version) is not None


class _AppState(object):

    def __init__(self, app):
        self.app = app
        self.view = None
        self.ready = False
        self.failed = False
        self.timeout = None
        # Only the latest refresh per still-live settings window is retained.
        self.pending = weakref.WeakKeyDictionary()


class Runtime(object):

    def __init__(self, api):
        self.api = api
        self.active = False
        self.states = {}
        self.hooks = []
        self.listeners = []
        self.view_type = None
        self.registered = False

    def start(self):
        if self.active:
            return
        # Check before installing anything, so incompatible clients fail open.
        for name in ('_update', 'as_setDataS', '_dispose'):
            if not callable(getattr(self.api.settings_type, name, None)):
                raise RuntimeError('Missing SettingsWindow.' + name)
        self.active = True
        self.view_type = self._make_view_type()
        self.api.register_view(VIEW_ALIAS, self.view_type)
        self.registered = True
        self._hook('_update', self._refresh)
        self._hook('as_setDataS', self._set_data)
        self._hook('_dispose', self._dispose_window)
        for event, listener in (
                (self.api.initialized_event, self._on_initialized),
                (self.api.destroyed_event, self._on_destroyed)):
            self.api.subscribe(event, listener)
            self.listeners.append((event, listener))
        for namespace in self.api.namespaces:
            app = self.api.get_app(namespace)
            if app is not None and app.initialized:
                self._ensure_app(app)

    def stop(self):
        self.active = False
        for event, listener in self.listeners:
            try:
                self.api.unsubscribe(event, listener)
            except Exception:
                _log.exception('Better Sense: listener cleanup failed.')
        self.listeners = []
        # Restore only our own current wrappers. Later mods may retain a wrapper
        # around ours; an inactive wrapper remains a transparent pass-through.
        for name, wrapper, original, owned in reversed(self.hooks):
            current = getattr(self.api.settings_type, name)
            if getattr(current, 'im_func', current) is wrapper:
                if owned:
                    setattr(self.api.settings_type, name, original)
                else:
                    delattr(self.api.settings_type, name)
        self.hooks = []
        for state in list(self.states.values()):
            self._cancel_timeout(state)
            state.ready = False
            state.failed = True
            if state.view is not None:
                self._disable_view(state.view)
            self._flush(state)
            try:
                self.api.destroy_view(state.app, VIEW_ALIAS)
            except Exception:
                _log.exception('Better Sense: view cleanup failed.')
        self.states.clear()
        if self.registered:
            try:
                self.api.unregister_view(VIEW_ALIAS, self.view_type)
            except Exception:
                _log.exception('Better Sense: view registration cleanup failed.')
            self.registered = False

    def _hook(self, name, handler):
        cls = self.api.settings_type
        original = getattr(cls, name)
        original = getattr(original, 'im_func', original)
        owned = name in cls.__dict__

        @wraps(original)
        def wrapper(window, *args, **kwargs):
            if not self.active:
                return original(window, *args, **kwargs)
            return handler(original, window, args, kwargs)

        self.hooks.append((name, wrapper, original, owned))
        setattr(cls, name, wrapper)

    def _make_view_type(self):
        runtime = self
        base = self.api.view_type

        class BetterSenseView(base):

            def _populate(self):
                # Flash may call ready() synchronously during base._populate().
                runtime._view_populating(self)
                try:
                    super(BetterSenseView, self)._populate()
                except Exception:
                    runtime._view_error(self, 'SWF population failed')
                    raise

            def ready(self):
                runtime._view_ready(self)

            def reportError(self, message):
                runtime._view_error(self, message)

            def readClipboard(self):
                try:
                    return runtime.api.read_clipboard()
                except Exception:
                    _log.exception('Better Sense: client clipboard read failed.')
                    return None

            def _dispose(self):
                runtime._view_disposed(self)
                super(BetterSenseView, self)._dispose()

        return BetterSenseView

    def _on_initialized(self, event):
        if self.active and event.ns in self.api.namespaces:
            app = self.api.get_app(event.ns)
            if app is not None:
                self._ensure_app(app)

    def _on_destroyed(self, event):
        state = self.states.pop(event.ns, None)
        if state is not None:
            self._cancel_timeout(state)
            state.pending.clear()
            state.view = None

    def _state_for(self, app):
        if app is None:
            return None
        try:
            state = self.states.get(app.appNS)
            # Game views hold weak proxies. Python 2 does not compare an ordinary
            # object equal to its proxy; use AppEntry's stable proxy identity.
            if state is not None:
                owner = getattr(state.app, 'proxy', state.app)
                candidate = getattr(app, 'proxy', app)
                if owner is candidate:
                    return state
            return None
        except ReferenceError:
            return None

    def _ensure_app(self, app):
        state = self._state_for(app)
        if state is not None:
            return state
        if app.appNS not in self.api.namespaces:
            return None
        previous = self.states.pop(app.appNS, None)
        if previous is not None:
            self._cancel_timeout(previous)
            previous.pending.clear()
        state = _AppState(app)
        self.states[app.appNS] = state
        try:
            self.api.load_view(app, VIEW_ALIAS)
        except Exception:
            self._fail(state, 'helper SWF could not be loaded')
        return state

    def _start_wait_timeout(self, state):
        # Lobby and battle applications preload the helper at different points in
        # their startup. A busy battle load can legitimately take more than two
        # seconds, so only time out once a real settings window is waiting for it.
        if state.timeout is None and not state.ready and not state.failed:
            state.timeout = self.api.schedule(
                LOAD_TIMEOUT_SECONDS, lambda: self._load_timeout(state))

    def _window_state(self, window):
        try:
            app = window.app
            if app is not None and app.initialized:
                return self._ensure_app(app)
        except Exception:
            _log.exception('Better Sense: settings app is unavailable; using stock controls.')
        return None

    def _refresh(self, original, window, args, kwargs):
        state = self._window_state(window)
        if state is not None and not state.ready and not state.failed:
            self._start_wait_timeout(state)
            # Defer the entire client refresh: its as_openTabS/video/counter calls
            # depend on as_setDataS having completed first.
            state.pending[window] = ('refresh', original, args, kwargs)
            return None
        return original(window, *args, **kwargs)

    def _set_data(self, original, window, args, kwargs):
        state = self._window_state(window)
        if state is not None and not state.ready and not state.failed:
            self._start_wait_timeout(state)
            pending = state.pending.get(window)
            if pending is None or pending[0] != 'refresh':
                state.pending[window] = ('data', original, args, kwargs)
            return None
        return self._send(state, original, window, args, kwargs)

    def _send(self, state, original, window, args, kwargs):
        helper = state.view if state is not None and state.ready and not state.failed else None
        started = False
        if helper is not None:
            try:
                helper.flashObject.beginModelUpdate()
                started = True
            except Exception:
                self._fail(state, 'beginModelUpdate failed')
        try:
            return original(window, *args, **kwargs)
        finally:
            if started:
                try:
                    helper.flashObject.endModelUpdate()
                except Exception:
                    self._fail(state, 'endModelUpdate failed')

    def _dispose_window(self, original, window, args, kwargs):
        for state in self.states.values():
            state.pending.pop(window, None)
        return original(window, *args, **kwargs)

    def _view_populating(self, view):
        state = self._state_for(view.app)
        if self.active and state is not None:
            state.view = view

    def _view_ready(self, view):
        state = self._state_for(view.app)
        if not self.active or state is None or state.failed or state.view is not view:
            # A timed-out SWF can finish loading later. It must not install
            # controls once the stock initial model has already been sent.
            self._disable_view(view)
            return
        state.ready = True
        self._cancel_timeout(state)
        self._flush(state)

    def _view_error(self, view, message):
        state = self._state_for(view.app)
        if state is not None and state.view is view:
            # Keep diagnostics bounded and single-line even for arbitrary SWF text.
            self._fail(state, str(message).replace('\n', ' ').replace('\r', ' ')[:240])

    def _view_disposed(self, view):
        state = self._state_for(view.app)
        if state is not None and state.view is view:
            state.view = None
            self._fail(state, 'helper view disposed')

    def _cancel_timeout(self, state):
        handle = state.timeout
        state.timeout = None
        if handle is not None:
            try:
                self.api.cancel(handle)
            except Exception:
                _log.exception('Better Sense: callback cleanup failed.')

    def _load_timeout(self, state):
        state.timeout = None
        if self.active and self._state_for(state.app) is state and not state.ready:
            self._fail(state, 'helper readiness timed out; using stock controls')

    def _fail(self, state, reason):
        first_failure = not state.failed
        if first_failure:
            _log.warning('Better Sense: %s.', reason)
        state.failed = True
        state.ready = False
        # Set failed first: disabling Flash may synchronously report an error.
        if first_failure and state.view is not None:
            self._disable_view(state.view)
        self._cancel_timeout(state)
        self._flush(state)

    def _disable_view(self, view):
        try:
            view.flashObject.disable()
        except Exception:
            _log.warning('Better Sense: helper disable failed; restart the client.')

    def _flush(self, state):
        pending = list(state.pending.items())
        state.pending.clear()
        for window, (kind, original, args, kwargs) in pending:
            try:
                if window.isDisposed() or self._state_for(window.app) is not state:
                    continue
                if kind == 'refresh':
                    original(window, *args, **kwargs)
                else:
                    self._send(state, original, window, args, kwargs)
            except Exception:
                _log.exception('Better Sense: deferred settings refresh failed.')
