package scaleform.clik.events
{
    import flash.events.Event;

    public final class SliderEvent extends Event
    {
        public static const VALUE_CHANGE:String = "valueChange";
        public var value:Number;

        public function SliderEvent(type:String, bubbles:Boolean = false,
                                    cancelable:Boolean = true, value:Number = 0)
        {
            super(type, bubbles, cancelable);
            this.value = value;
        }
    }
}
