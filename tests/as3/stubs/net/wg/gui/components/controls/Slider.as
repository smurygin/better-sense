package net.wg.gui.components.controls
{
    import flash.display.Sprite;
    import scaleform.clik.events.SliderEvent;

    /** Models verified CLIK setter/event behavior, not native rendering. */
    public final class Slider extends Sprite
    {
        public var minimum:Number = 0;
        public var maximum:Number = 2;
        public var maxAvailableValue:Number = NaN;
        public var snapInterval:Number = 0.1;
        public var snapping:Boolean = true;
        public var enabled:Boolean = true;
        private var number:Number = 0;
        private var logicalWidth:Number = 200;

        public function Slider()
        {
            graphics.beginFill(0);
            graphics.drawRect(0, 0, 200, 20);
            graphics.endFill();
        }

        override public function get width():Number { return logicalWidth; }
        override public function set width(value:Number):void { logicalWidth = value; }
        public function get value():Number { return number; }
        public function set value(value:Number):void
        {
            number = Math.max(minimum, Math.min(maximum, value));
            if (snapping)
                number = Math.round(number / snapInterval) * snapInterval;
            dispatchEvent(new SliderEvent(SliderEvent.VALUE_CHANGE, false, true, number));
        }
        public function get position():Number { return number; }
        public function set position(value:Number):void { number = value; }
        public function invalidate():void {}
    }
}
