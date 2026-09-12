package
{
    import flash.display.InteractiveObject;

    /** Minimal host protocol; no native game library is loaded by these tests. */
    public final class App
    {
        public static var focused:InteractiveObject;
        public static var tooltip:String = "";
        public static var utils:Object = {
            classFactory: { getComponent: createComponent },
            focusHandler: { getFocus: getFocus, setFocus: setFocus }
        };
        public static var toolTipMgr:Object = {
            showComplex: function(text:String):void { tooltip = text; },
            hide: function():void { tooltip = ""; }
        };

        private static function createComponent(linkage:String, type:Class, properties:Object):Object
        {
            var result:Object = new type();
            for (var key:String in properties)
                result[key] = properties[key];
            return result;
        }

        private static function getFocus(index:uint):InteractiveObject
        {
            return focused;
        }

        private static function setFocus(target:InteractiveObject):void
        {
            focused = target;
        }
    }
}
