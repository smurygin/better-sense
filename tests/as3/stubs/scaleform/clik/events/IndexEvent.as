package scaleform.clik.events
{
    import flash.events.Event;

    public final class IndexEvent extends Event
    {
        public static const INDEX_CHANGE:String = "indexChange";
        public var index:Number;
        public var lastIndex:Number;
        public var data:Object;

        public function IndexEvent(type:String, bubbles:Boolean = true, cancelable:Boolean = false,
            index:Number = 0, lastIndex:Number = 0, data:Object = null)
        {
            super(type, bubbles, cancelable);
            this.index = index;
            this.lastIndex = lastIndex;
            this.data = data;
        }
    }
}
