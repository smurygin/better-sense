package better_sense
{
    import flash.display.DisplayObject;
    import flash.display.DisplayObjectContainer;
    import flash.display.Stage;
    import flash.events.Event;
    import flash.utils.Dictionary;
    import net.wg.gui.lobby.settings.ControlsSettings;
    import net.wg.gui.lobby.settings.SettingsWindow;
    import net.wg.infrastructure.base.AbstractView;
    import net.wg.infrastructure.events.LifeCycleEvent;

    /** Invisible service: native settings retain ownership of the visible controls. */
    public class BetterSenseView extends AbstractView
    {
        public var ready:Function;
        public var reportError:Function;

        private var observedStage:Stage;
        private var windows:Dictionary = new Dictionary();
        private var modelDepth:uint = 0;
        private var active:Boolean = false;

        override protected function onPopulate():void
        {
            super.onPopulate();
            mouseEnabled = false;
            mouseChildren = false;
            tabEnabled = false;
            active = true;
            observedStage = App.stage;
            observedStage.addEventListener(Event.ADDED, onAdded, true, 1000);
            scan(observedStage);
            if (ready != null)
                ready();
        }

        override protected function allowHandleInput():Boolean
        {
            return false;
        }

        override protected function get autoShowViewProperty():int
        {
            return SHOW_VIEW_PROP_FORBIDDEN;
        }

        /** Called synchronously around the original Python as_setDataS call. */
        public function beginModelUpdate():void
        {
            if (!active)
                return;
            modelDepth++;
            scan(observedStage);
        }

        public function endModelUpdate():void
        {
            if (!active)
                return;
            if (modelDepth == 0)
            {
                logError("Unbalanced settings model update");
                return;
            }
            modelDepth--;
            if (modelDepth == 0)
                refreshWindows();
        }

        public function isModelUpdating():Boolean
        {
            return modelDepth > 0;
        }

        private function onAdded(event:Event):void
        {
            var target:DisplayObject = event.target as DisplayObject;
            if (target is SettingsWindow)
                attachWindow(SettingsWindow(target));
            else if (target is ControlsSettings)
                attachControls(ControlsSettings(target));
        }

        private function scan(container:DisplayObjectContainer):void
        {
            if (container == null)
                return;
            if (container is SettingsWindow)
                attachWindow(SettingsWindow(container));
            if (container is ControlsSettings)
            {
                attachControls(ControlsSettings(container));
                return;
            }
            // Attaching controls can add children, so do not cache numChildren.
            for (var index:int = 0; index < container.numChildren; index++)
            {
                var child:DisplayObjectContainer = container.getChildAt(index) as DisplayObjectContainer;
                if (child != null && child != this)
                    scan(child);
            }
        }

        private function attachWindow(window:SettingsWindow):void
        {
            if (!active || windows[window] != null || window.view == null)
                return;
            try
            {
                windows[window] = new SettingsBinding(window, isModelUpdating, logError);
                window.addEventListener(LifeCycleEvent.ON_BEFORE_DISPOSE, onWindowDispose, false, 1000);
            }
            catch (error:Error)
            {
                logError("Cannot attach settings window: " + error.message);
            }
        }

        private function attachControls(controls:ControlsSettings):void
        {
            var ancestor:DisplayObject = controls.parent;
            while (ancestor != null && !(ancestor is SettingsWindow))
                ancestor = ancestor.parent;
            if (ancestor == null)
                return;
            var window:SettingsWindow = SettingsWindow(ancestor);
            attachWindow(window);
            var binding:SettingsBinding = windows[window];
            if (binding != null)
                binding.attach(controls);
        }

        private function refreshWindows():void
        {
            for each (var binding:SettingsBinding in windows)
                binding.refresh();
        }

        private function onWindowDispose(event:LifeCycleEvent):void
        {
            var window:SettingsWindow = event.currentTarget as SettingsWindow;
            window.removeEventListener(LifeCycleEvent.ON_BEFORE_DISPOSE, onWindowDispose);
            var binding:SettingsBinding = windows[window];
            delete windows[window];
            if (binding != null)
                binding.dispose();
        }

        private function logError(message:String):void
        {
            disable();
            if (reportError != null)
                reportError(message);
            else
                trace("[Better Sense] " + message);
        }

        /** Fail open before Python resumes stock updates; safe to call repeatedly. */
        public function disable():void
        {
            active = false;
            if (observedStage != null)
                observedStage.removeEventListener(Event.ADDED, onAdded, true);
            for (var key:Object in windows)
            {
                SettingsWindow(key).removeEventListener(LifeCycleEvent.ON_BEFORE_DISPOSE, onWindowDispose);
                SettingsBinding(windows[key]).dispose();
                delete windows[key];
            }
            observedStage = null;
            modelDepth = 0;
        }

        override protected function onBeforeDispose():void
        {
            disable();
            ready = null;
            reportError = null;
            super.onBeforeDispose();
        }
    }
}
