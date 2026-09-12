package net.wg.gui.components.controls
{
    import flash.display.MovieClip;
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.text.TextField;
    import scaleform.clik.events.ComponentEvent;

    /** Supplies only the native control protocol needed by SensitivityInput. */
    public final class TextInput extends Sprite
    {
        public var textField:TextField;
        public var highlightMc:MovieClip = new MovieClip();
        public var enabled:Boolean = true;
        public var highlight:Boolean = false;
        public var maxChars:uint = 0;
        public var extractEscapes:Boolean = false;
        public var wasDisposed:Boolean = false;
        private var content:String = "";

        public function TextInput()
        {
            textField = createField();
        }

        private function createField():TextField
        {
            var result:TextField = new TextField();
            result.type = "input";
            result.text = content;
            result.addEventListener(Event.CHANGE, nativeChange, false, 0);
            addChild(result);
            return result;
        }

        private function nativeChange(event:Event):void
        {
            content = textField.text;
            dispatchEvent(new Event(Event.CHANGE));
        }

        public function get text():String { return content; }
        public function set text(value:String):void { content = value; }
        public function validateNow():void { textField.text = content; }

        public function replaceSkinField():TextField
        {
            var old:TextField = textField;
            old.removeEventListener(Event.CHANGE, nativeChange);
            removeChild(old);
            textField = createField();
            dispatchEvent(new ComponentEvent(ComponentEvent.STATE_CHANGE));
            return old;
        }

        public function dispose():void
        {
            wasDisposed = true;
            textField.removeEventListener(Event.CHANGE, nativeChange);
        }
    }
}
