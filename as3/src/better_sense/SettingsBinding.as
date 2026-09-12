package better_sense
{
    import flash.display.InteractiveObject;
    import flash.events.IEventDispatcher;
    import flash.ui.Keyboard;
    import net.wg.gui.components.advanced.ViewStack;
    import net.wg.gui.components.controls.Slider;
    import net.wg.gui.events.ViewStackEvent;
    import net.wg.gui.lobby.settings.ControlsSettings;
    import net.wg.gui.lobby.settings.SettingsWindow;
    import net.wg.infrastructure.events.LifeCycleEvent;
    import scaleform.clik.constants.InputValue;
    import scaleform.clik.events.ButtonEvent;
    import scaleform.clik.events.InputEvent;
    import scaleform.clik.core.UIComponent;

    /** Binds one native window; values and dirty state remain in its stock model. */
    public final class SettingsBinding
    {
        private static const IDS:Array = [
            "mouseArcadeSens", "mouseSniperSens", "mouseAssaultSens",
            "mouseStrategicSens", "mouseAssistAimSens"
        ];

        private var window:SettingsWindow;
        private var stack:ViewStack;
        private var inputDispatcher:IEventDispatcher;
        private var controls:ControlsSettings;
        private var rows:Vector.<SensitivityInput> = new Vector.<SensitivityInput>();
        private var externalModelUpdate:Function;
        private var report:Function;
        private var tabDepth:uint = 0;
        private var disposed:Boolean = false;

        public function SettingsBinding(target:SettingsWindow, updating:Function, reportError:Function)
        {
            window = target;
            stack = target.view;
            if (stack == null || window.applyBtn == null || window.submitBtn == null || window.cancelBtn == null)
                throw new Error("Incomplete native SettingsWindow");
            externalModelUpdate = updating;
            report = reportError;
            stack.addEventListener(ViewStackEvent.NEED_UPDATE, beforeTabUpdate, false, 1000);
            stack.addEventListener(ViewStackEvent.NEED_UPDATE, afterTabUpdate, false, -1000);
            stack.addEventListener(ViewStackEvent.VIEW_CHANGED, beforeTabUpdate, false, 1000);
            stack.addEventListener(ViewStackEvent.VIEW_CHANGED, afterTabUpdate, false, -1000);
            window.addEventListener(InputEvent.INPUT, onInput, true, 1000);
            inputDispatcher = window.window as IEventDispatcher;
            if (inputDispatcher != null)
                inputDispatcher.addEventListener(InputEvent.INPUT, onInput, true, 1000);
            window.applyBtn.addEventListener(ButtonEvent.CLICK, onApply, false, 1000);
            window.submitBtn.addEventListener(ButtonEvent.CLICK, onApply, false, 1000);
            window.cancelBtn.addEventListener(ButtonEvent.CLICK, onCancel, false, 1000);
        }

        public function attach(target:ControlsSettings):void
        {
            if (disposed || controls == target)
                return;
            detachControls();
            controls = target;
            controls.addEventListener(LifeCycleEvent.ON_BEFORE_DISPOSE, onControlsDispose, false, 1000);
            try
            {
                for each (var id:String in IDS)
                {
                    var slider:Slider = target[id + "Slider"] as Slider;
                    if (slider == null)
                        throw new Error("Missing sensitivity slider " + id);
                    rows.push(new SensitivityInput(target, slider, id, isModelUpdating));
                }
                refresh();
            }
            catch (error:Error)
            {
                detachControls();
                report("Cannot attach sensitivity fields: " + error.message);
            }
        }

        private function isModelUpdating():Boolean
        {
            return tabDepth > 0 || Boolean(externalModelUpdate());
        }

        private function beforeTabUpdate(event:ViewStackEvent):void
        {
            tabDepth++;
            if (event.view is ControlsSettings)
                attach(ControlsSettings(event.view));
        }

        private function afterTabUpdate(event:ViewStackEvent):void
        {
            if (tabDepth > 0)
                tabDepth--;
            refresh();
        }

        public function refresh():void
        {
            if (disposed)
                return;
            for each (var row:SensitivityInput in rows)
                row.refresh();
        }

        private function onApply(event:ButtonEvent):void
        {
            for each (var row:SensitivityInput in rows)
                row.commit();
        }

        private function onCancel(event:ButtonEvent):void
        {
            // The native window discards its complete change set, including edits
            // already previewed through a field. Do not re-commit on focus loss.
            for each (var row:SensitivityInput in rows)
                row.abandon();
        }

        private function onInput(event:InputEvent):void
        {
            if (disposed || event.handled || controls == null || !controls.visible)
                return;
            var focus:InteractiveObject = App.utils.focusHandler.getFocus(0);
            var index:int;
            var row:SensitivityInput;
            for (index = 0; index < rows.length; index++)
            {
                row = rows[index];
                if (row.ownsFocus(focus))
                    break;
            }
            var inField:Boolean = index < rows.length;
            var code:uint = event.details.code;
            if (!inField)
            {
                if (code != Keyboard.TAB)
                    return;
                for (index = 0; index < rows.length; index++)
                    if (focus == rows[index].slider)
                        break;
                if (index == rows.length || (index == 0 && event.details.shiftKey))
                    return;
            }
            else if (code != Keyboard.ENTER && code != Keyboard.ESCAPE && code != Keyboard.TAB)
                return;

            var next:InteractiveObject = code == Keyboard.TAB ? nextFocus(index, inField, event.details.shiftKey) : null;
            if (code == Keyboard.TAB && next == null)
                return; // Leave boundaries and unrelated controls to native navigation.

            event.handled = true;
            event.preventDefault();
            event.stopImmediatePropagation();
            if (event.details.value != InputValue.KEY_DOWN)
                return;
            if (code == Keyboard.ENTER)
                rows[index].commit();
            else if (code == Keyboard.ESCAPE)
                rows[index].cancelEdit();
            else
            {
                if (inField)
                    rows[index].commit();
                App.utils.focusHandler.setFocus(next);
            }
        }

        private function nextFocus(index:int, inField:Boolean, backwards:Boolean):InteractiveObject
        {
            var direction:int = backwards ? -1 : 1;
            var position:int = index * 2 + (inField ? 1 : 0) + direction;
            while (position >= 0 && position < rows.length * 2)
            {
                var row:SensitivityInput = rows[int(position / 2)];
                var candidate:InteractiveObject = position % 2 == 0 ? row.slider : row.input;
                if (canFocus(candidate))
                    return candidate;
                position += direction;
            }
            return !backwards && canFocus(controls.mouseHorzInvertCheckbox) ? controls.mouseHorzInvertCheckbox : null;
        }

        private function canFocus(target:InteractiveObject):Boolean
        {
            var component:UIComponent = target as UIComponent;
            if (target == null || target.stage == null || !target.visible ||
                (component != null && (!component.enabled || !component.focusable)))
                return false;
            return true;
        }

        private function onControlsDispose(event:LifeCycleEvent):void
        {
            detachControls();
        }

        private function detachControls():void
        {
            if (controls != null)
                controls.removeEventListener(LifeCycleEvent.ON_BEFORE_DISPOSE, onControlsDispose);
            for each (var row:SensitivityInput in rows)
                row.dispose();
            rows.length = 0;
            controls = null;
        }

        public function dispose():void
        {
            if (disposed)
                return;
            disposed = true;
            detachControls();
            stack.removeEventListener(ViewStackEvent.NEED_UPDATE, beforeTabUpdate);
            stack.removeEventListener(ViewStackEvent.NEED_UPDATE, afterTabUpdate);
            stack.removeEventListener(ViewStackEvent.VIEW_CHANGED, beforeTabUpdate);
            stack.removeEventListener(ViewStackEvent.VIEW_CHANGED, afterTabUpdate);
            window.removeEventListener(InputEvent.INPUT, onInput, true);
            if (inputDispatcher != null)
                inputDispatcher.removeEventListener(InputEvent.INPUT, onInput, true);
            window.applyBtn.removeEventListener(ButtonEvent.CLICK, onApply);
            window.submitBtn.removeEventListener(ButtonEvent.CLICK, onApply);
            window.cancelBtn.removeEventListener(ButtonEvent.CLICK, onCancel);
            window = null;
            stack = null;
            inputDispatcher = null;
            externalModelUpdate = null;
            report = null;
        }
    }
}
