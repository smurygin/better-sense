package scaleform.clik.events
{
    import flash.events.Event;

    public final class ButtonEvent extends Event
    {
        public static const CLICK:String = "buttonClick";

        public function ButtonEvent(type:String, bubbles:Boolean = true, cancelable:Boolean = true)
        {
            super(type, bubbles, cancelable);
        }
    }
}
