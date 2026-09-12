"""Exercise the actual bridge with fake client lifecycles, without the game."""

import os
import sys
import unittest
import weakref

MOD_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        'res', 'scripts', 'client', 'gui', 'mods')
sys.path.insert(0, MOD_PATH)
from better_sense.runtime import Runtime, VIEW_ALIAS, is_supported_version


class FakeApp(object):

    def __init__(self, namespace):
        self.appNS = namespace
        self.initialized = True
        self.proxy = weakref.proxy(self)


class FakeFlash(object):

    def __init__(self, trace):
        self.trace = trace
        self.begin_error = False
        self.end_error = False

    def beginModelUpdate(self):
        self.trace.append('begin')
        if self.begin_error:
            raise RuntimeError('missing method')

    def endModelUpdate(self):
        self.trace.append('end')
        if self.end_error:
            raise RuntimeError('broken helper')

    def disable(self):
        self.trace.append('disable')


class FakeView(object):

    def _populate(self):
        pass

    def _dispose(self):
        pass


class FakeEvent(object):

    def __init__(self, namespace):
        self.ns = namespace


class FakeAPI(object):
    namespaces = ('scaleform/lobby', 'scaleform/battle')
    initialized_event = 'initialized'
    destroyed_event = 'destroyed'
    view_type = FakeView

    def __init__(self, settings_type):
        self.settings_type = settings_type
        self.apps = dict((ns, FakeApp(ns)) for ns in self.namespaces)
        self.listeners = {}
        self.callbacks = {}
        self.loaded = []
        self.destroyed = []
        self.registered = {}
        self.next_callback = 0
        self.load_error = False

    def get_app(self, namespace):
        return self.apps.get(namespace)

    def subscribe(self, event, listener):
        self.listeners[event] = listener

    def unsubscribe(self, event, listener):
        assert self.listeners[event] == listener
        del self.listeners[event]

    def register_view(self, alias, view_type):
        self.registered[alias] = view_type

    def unregister_view(self, alias, view_type):
        assert self.registered[alias] is view_type
        del self.registered[alias]

    def load_view(self, app, alias):
        if self.load_error:
            raise RuntimeError('SWF not found')
        self.loaded.append((app, alias))

    def destroy_view(self, app, alias):
        self.destroyed.append((app, alias))

    def schedule(self, delay, callback):
        self.next_callback += 1
        self.callbacks[self.next_callback] = callback
        return self.next_callback

    def cancel(self, handle):
        del self.callbacks[handle]

    def fire_callback(self, handle):
        callback = self.callbacks.pop(handle)
        callback()


class RuntimeTest(unittest.TestCase):

    def setUp(self):
        class SettingsBase(object):

            def as_setDataS(self, value):
                self.trace.append(('data', value))
                if self.stock_error:
                    raise ValueError('original settings failure')

        class SettingsWindow(SettingsBase):

            def __init__(self, app):
                # This is how the real loader supplies an app to game views.
                self.app = weakref.proxy(app)
                self.trace = []
                self.value = 0.123456
                self.disposed = False
                self.stock_error = False

            def _update(self):
                self.as_setDataS(self.value)
                self.trace.append('open_tab')

            def _dispose(self):
                self.disposed = True

            def isDisposed(self):
                return self.disposed

        self.window_type = SettingsWindow
        self.api = FakeAPI(SettingsWindow)
        self.runtime = Runtime(self.api)
        self.runtime.start()
        self.lobby = self.api.apps[self.api.namespaces[0]]
        self.battle = self.api.apps[self.api.namespaces[1]]
        self.window = SettingsWindow(self.lobby)

    def tearDown(self):
        self.runtime.stop()

    def make_helper(self, app=None, ready=True, trace=None):
        view = self.runtime.view_type()
        view.app = weakref.proxy(app or self.lobby)
        view.flashObject = FakeFlash(self.window.trace if trace is None else trace)
        view._populate()
        if ready:
            view.ready()
        return view

    def test_preloads_once_per_app(self):
        self.assertEqual(len(self.api.loaded), 2)
        self.api.listeners['initialized'](FakeEvent(self.lobby.appNS))
        self.assertEqual(len(self.api.loaded), 2)
        self.assertEqual(set(self.api.registered), set([VIEW_ALIAS]))

    def test_preloaded_app_and_view_weak_proxy_share_one_state(self):
        state = self.runtime.states[self.lobby.appNS]
        self.assertIs(self.runtime._state_for(self.window.app), state)
        self.make_helper()
        self.window.as_setDataS(0.5)
        self.assertIs(self.runtime.states[self.lobby.appNS], state)
        self.assertEqual(len(self.api.loaded), 2)
        self.assertEqual(self.window.trace, ['begin', ('data', 0.5), 'end'])

    def test_defers_entire_refresh_and_uses_latest_model(self):
        self.window._update()
        self.window.value = 0.654321
        self.window._update()
        self.assertEqual(self.window.trace, [])
        self.assertEqual(len(self.runtime.states[self.lobby.appNS].pending), 1)
        self.make_helper()
        self.assertEqual(self.window.trace,
                         ['begin', ('data', 0.654321), 'end', 'open_tab'])

    def test_direct_data_keeps_only_latest_payload(self):
        self.window.as_setDataS(0.12)
        self.window.as_setDataS(0.23)
        self.make_helper()
        self.assertEqual(self.window.trace, ['begin', ('data', 0.23), 'end'])

    def test_queued_refresh_takes_precedence_over_partial_data(self):
        self.window._update()
        self.window.value = 0.4
        self.window.as_setDataS(0.3)
        self.make_helper()
        self.assertEqual(self.window.trace,
                         ['begin', ('data', 0.4), 'end', 'open_tab'])

    def test_battle_readiness_does_not_flush_lobby(self):
        battle_window = self.window_type(self.battle)
        self.window._update()
        battle_window._update()
        self.make_helper(self.battle, trace=battle_window.trace)
        self.assertEqual(self.window.trace, [])
        self.assertEqual(battle_window.trace,
                         ['begin', ('data', 0.123456), 'end', 'open_tab'])

    def test_disposed_windows_are_never_replayed(self):
        self.window._update()
        self.window._dispose()
        self.make_helper()
        self.assertEqual(self.window.trace, [])

    def test_disposed_flag_also_protects_flush(self):
        self.window._update()
        self.window.disposed = True
        self.make_helper()
        self.assertEqual(self.window.trace, [])

    def test_timeout_restores_stock_window_and_late_ready_is_ignored(self):
        self.window._update()
        state = self.runtime.states[self.lobby.appNS]
        self.api.fire_callback(state.timeout)
        self.assertEqual(self.window.trace, [('data', 0.123456), 'open_tab'])
        self.make_helper()
        self.window.as_setDataS(0.5)
        self.assertEqual(self.window.trace[-2:], ['disable', ('data', 0.5)])
        self.assertFalse(state.ready)

    def test_end_is_called_even_when_original_raises(self):
        self.make_helper()
        self.window.stock_error = True
        with self.assertRaises(ValueError):
            self.window.as_setDataS(0.6)
        self.assertEqual(self.window.trace, ['begin', ('data', 0.6), 'end'])

    def test_missing_flash_method_still_delivers_stock_data_once(self):
        helper = self.make_helper()
        helper.flashObject.begin_error = True
        self.window.as_setDataS(0.7)
        self.assertEqual(self.window.trace, ['begin', 'disable', ('data', 0.7)])
        self.assertTrue(self.runtime.states[self.lobby.appNS].failed)

    def test_end_failure_disables_helper_after_single_stock_delivery(self):
        helper = self.make_helper()
        helper.flashObject.end_error = True
        self.window.as_setDataS(0.7)
        self.assertEqual(self.window.trace, ['begin', ('data', 0.7), 'end', 'disable'])
        self.assertTrue(self.runtime.states[self.lobby.appNS].failed)

    def test_reported_error_flushes_waiting_window(self):
        self.window._update()
        helper = self.make_helper(ready=False)
        helper.reportError('component factory unavailable')
        self.assertEqual(self.window.trace, ['disable', ('data', 0.123456), 'open_tab'])

    def test_disposing_helper_releases_waiting_window(self):
        self.window._update()
        helper = self.make_helper(ready=False)
        helper._dispose()
        self.assertEqual(self.window.trace, [('data', 0.123456), 'open_tab'])

    def test_app_destroy_cancels_callbacks_and_drops_pending(self):
        self.window._update()
        timeout = self.runtime.states[self.lobby.appNS].timeout
        self.api.listeners['destroyed'](FakeEvent(self.lobby.appNS))
        self.assertNotIn(timeout, self.api.callbacks)
        self.assertNotIn(self.lobby.appNS, self.runtime.states)
        self.assertEqual(self.window.trace, [])

    def test_new_application_gets_new_helper(self):
        old_state = self.runtime.states[self.lobby.appNS]
        self.window._update()
        new_app = FakeApp(self.lobby.appNS)
        self.api.apps[new_app.appNS] = new_app
        self.api.listeners['initialized'](FakeEvent(new_app.appNS))
        self.assertIsNot(self.runtime.states[new_app.appNS], old_state)
        self.assertEqual(len(old_state.pending), 0)
        self.assertIs(self.api.loaded[-1][0], new_app)

    def test_cleanup_flushes_stock_data_and_restores_inherited_method(self):
        self.window._update()
        self.runtime.stop()
        self.assertEqual(self.window.trace, [('data', 0.123456), 'open_tab'])
        self.assertEqual(self.api.callbacks, {})
        self.assertEqual(self.api.listeners, {})
        self.assertEqual(self.api.registered, {})
        self.assertNotIn('as_setDataS', self.window_type.__dict__)

    def test_later_mod_wrapper_is_not_removed_and_old_hook_is_inert(self):
        ours = self.window_type.as_setDataS

        def later_mod(window, value):
            window.trace.append('later_mod')
            return ours(window, value)

        self.window_type.as_setDataS = later_mod
        self.runtime.stop()
        current = self.window_type.as_setDataS
        self.assertIs(getattr(current, 'im_func', current), later_mod)
        self.window.as_setDataS(0.8)
        self.assertEqual(self.window.trace, ['later_mod', ('data', 0.8)])

    def test_preexisting_mod_is_preserved(self):
        self.runtime.stop()
        original = self.window_type._update

        def previous_mod(window):
            window.trace.append('previous_mod')
            original(window)

        self.window_type._update = previous_mod
        self.runtime.start()
        self.make_helper()
        self.window._update()
        self.assertEqual(self.window.trace,
                         ['previous_mod', 'begin', ('data', 0.123456), 'end', 'open_tab'])
        self.runtime.stop()
        current = self.window_type._update
        self.assertIs(getattr(current, 'im_func', current), previous_mod)

    def test_missing_helper_asset_fails_open(self):
        self.runtime.stop()
        self.api.load_error = True
        self.runtime.start()
        self.window._update()
        self.assertEqual(self.window.trace, [('data', 0.123456), 'open_tab'])
        self.assertEqual(self.api.callbacks, {})

    def test_missing_client_api_is_detected_before_install(self):
        self.runtime.stop()
        self.window_type._update = None
        with self.assertRaises(RuntimeError):
            self.runtime.start()
        self.assertEqual(self.api.registered, {})
        self.assertFalse(self.runtime.active)


class VersionTest(unittest.TestCase):

    def test_pinned_release_and_145_hotfixes(self):
        for version in (' v.1.45.0.0 #2272 ', '1.45', '1.45.0.1', 'v1.45.1.0'):
            self.assertTrue(is_supported_version(version), version)

    def test_other_patches_and_unavailable_version_fail_closed(self):
        for version in ('1.44.0.0', '1.46', '1.450', '11.45', '', None, '1.45beta'):
            self.assertFalse(is_supported_version(version), repr(version))


if __name__ == '__main__':
    unittest.main()
