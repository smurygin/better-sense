# -*- coding: utf-8 -*-
"""Game-specific adapter; importing this module does not modify the client."""

import logging

from .runtime import Runtime, is_supported_version

_log = logging.getLogger('better_sense')
_runtime = None


def init():
    global _runtime
    if _runtime is not None:
        return
    try:
        from helpers import getClientVersion
        version = getClientVersion()
        if not is_supported_version(version):
            _log.warning('Better Sense disabled: unsupported client %r (requires 1.45).', version)
            return
        api = _ClientAPI()
        runtime = Runtime(api)
        _runtime = runtime
        runtime.start()
        _log.info('Better Sense loaded for Mir Tankov 1.45.')
    except Exception:
        _log.exception('Better Sense disabled: client API initialization failed.')
        fini()


def fini():
    global _runtime
    runtime = _runtime
    _runtime = None
    if runtime is not None:
        runtime.stop()


class _ClientAPI(object):
    """Small adapter keeps the lifecycle logic testable without BigWorld."""

    def __init__(self):
        import BigWorld
        from frameworks.wulf import WindowLayer
        from gui.Scaleform.daapi.view.common.settings.SettingsWindow import SettingsWindow
        from gui.Scaleform.framework import g_entitiesFactories, ViewSettings, ScopeTemplates
        from gui.Scaleform.framework.entities.View import View
        from gui.Scaleform.framework.managers.loaders import SFViewLoadParams
        from gui.app_loader.settings import APP_NAME_SPACE
        from gui.shared import g_eventBus, EVENT_BUS_SCOPE
        from gui.shared.events import AppLifeCycleEvent
        from helpers import dependency
        from skeletons.gui.app_loader import IAppLoader

        self.settings_type = SettingsWindow
        self.view_type = View
        self.namespaces = (APP_NAME_SPACE.SF_LOBBY, APP_NAME_SPACE.SF_BATTLE)
        self.initialized_event = AppLifeCycleEvent.INITIALIZED
        self.destroyed_event = AppLifeCycleEvent.DESTROYED
        self.schedule = BigWorld.callback
        self.cancel = BigWorld.cancelCallback
        self._loader = dependency.instance(IAppLoader)
        self._bus = g_eventBus
        self._scope = EVENT_BUS_SCOPE.GLOBAL
        self._factory = g_entitiesFactories
        self._view_settings = ViewSettings
        self._view_scope = ScopeTemplates.GLOBAL_SCOPE
        self._layer = WindowLayer.HIDDEN_SERVICE_LAYOUT
        self._load_params = SFViewLoadParams

    def get_app(self, namespace):
        return self._loader.getApp(namespace)

    def subscribe(self, event, listener):
        self._bus.addListener(event, listener, self._scope)

    def unsubscribe(self, event, listener):
        self._bus.removeListener(event, listener, self._scope)

    def register_view(self, alias, view_type):
        settings = self._view_settings(
            alias=alias, clazz=view_type, url='better_sense.swf',
            layer=self._layer, scope=self._view_scope, canDrag=False,
            canClose=False, isModal=False, isCentered=False)
        self._factory.addSettings(settings)

    def unregister_view(self, alias, view_type):
        settings = self._factory.getSettings(alias)
        if settings is not None and settings.clazz is view_type:
            self._factory.removeSettings(alias)

    def load_view(self, app, alias):
        app.loadView(self._load_params(alias))

    def destroy_view(self, app, alias):
        manager = app.containerManager
        if manager is not None:
            manager.destroyViews(alias)

    def read_clipboard(self):
        """Read Unicode text synchronously through the Windows client process."""
        import ctypes

        cf_unicode_text = 13
        user32 = ctypes.windll.user32
        kernel32 = ctypes.windll.kernel32
        user32.GetClipboardData.restype = ctypes.c_void_p
        kernel32.GlobalLock.argtypes = (ctypes.c_void_p,)
        kernel32.GlobalLock.restype = ctypes.c_void_p

        if not user32.IsClipboardFormatAvailable(cf_unicode_text):
            return None
        if not user32.OpenClipboard(None):
            return None
        handle = None
        address = None
        try:
            handle = user32.GetClipboardData(cf_unicode_text)
            if not handle:
                return None
            address = kernel32.GlobalLock(handle)
            if not address:
                return None
            return ctypes.wstring_at(address)
        finally:
            if address:
                kernel32.GlobalUnlock(handle)
            user32.CloseClipboard()
