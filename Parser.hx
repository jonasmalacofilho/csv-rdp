import haxe.Utf8;

typedef Field = String;
typedef Record = Array<Field>;

/*
    TODO Missing newline handling and multiple records

    The Grammar
 
    Terminals:

        sep                       separator character, usually `,`
        esc                       escape character, usually `"`
        eol                       end-on-line sequence, usually `\n` or `\r\n`

    Non-terminals:

        safe                 ::=  !( esc | sep | eol )
        escaped              ::=  safe | esc esc | sep | eol
        non_escaped_string   ::=  "" | safe non_escaped_string
        escaped_string       ::=  "" | escaped escaped_string
        field                ::=  esc escaped_string esc | non_escaped_string
        record               ::=  field | field sep record
        csv                  ::=  record | record eol csv

    Notes:

        The resulting empty record after a terminating end-of-line sequence in
        a text is automatically striped.
*/
class Parser {

    var sep:String;
    var esc:String;
    var eol:String;
    var str:String;
    var len:Int;
    var pos:Int;

    function new(str, sep, esc, eol)
    {
        if (Utf8.length(sep) != 1)
            throw 'Separator string "$sep" not allowed, only single char';
        if (Utf8.length(esc) != 1)
            throw 'Escape string "$esc" not allowed, only single char';
        if (Utf8.length(eol) < 1)
            throw "EOL sequence can't be empty";
        if (StringTools.startsWith(eol, esc))
            throw 'EOL sequence can\'t start with the esc character ($esc)';

        this.sep = sep;
        this.esc = esc;
        this.eol = eol;
        this.str = str;
        len = Utf8.length(str);
        pos = 0;
    }

    // Peek at the next token
    function peek(?skip=0)
    {
        var p = pos;
        var ret = null;
        while (skip-- >= 0) {
            if (ret != null)
                p += Utf8.length(ret);

            if (p >= len) {
                return null;
            }

            var eolsize = Utf8.length(eol);
            if (p + eolsize - 1 < len && Utf8.sub(str, p, eolsize) == eol)
                ret = eol;
            else
                ret = Utf8.sub(str, p, 1);
        }
        return ret;
    }

    // Pop the next token
    function next(?skip=0)
    {
        var ret = null;
        while (skip-- >= 0) {
            ret = peek();
            if (ret != null)
                pos += Utf8.length(ret);
        }
        return ret;
    }

    function safe()
    {
        var cur = peek();
        if (cur == sep || cur == esc || cur == eol)
            return null;
        return next();
    }

    function escaped()
    {
        var cur = peek();
        // It follows from the grammar that the only forbidden result is an isolated escape
        if (cur == esc) {
            if (peek(1) != esc)
                return null;
            return next(1);
        }
        return next();
    }

    function escapedString()
    {
        var buf = new StringBuf();
        var x = escaped();
        while (x != null) {
            buf.add(x);
            x = escaped();
        }
        return buf.toString();
    }

    function nonEscapedString()
    {
        var buf = new StringBuf();
        var x = safe();
        while (x != null) {
            buf.add(x);
            x = safe();
        }
        return buf.toString();
    }

    function field()
    {
        var cur = peek();
        if (cur == esc) {
            next();
            var s = escapedString();
            var fi = next();
            if (fi != esc)
                throw 'Missing $esc at the end of escaped field ${s.length>15 ? s.substr(0,10)+"[...]" : s}';
            return s;
        } else {
            return nonEscapedString();
        }
    }

    function record()
    {
        var r = [];
        r.push(field());
        while (peek() == sep) {
            next();
            r.push(field());
        }
        return r;
    }

    function records()
    {
        var r = [];
        r.push(record());
        var nl = next();
        while (nl == eol) {
            if (peek() == null)
                break;  // don't append an empty record for eol terminating string
            r.push(record());
            nl = next();
        }
        if (peek() != null)
            throw 'Unexpected "${peek()}" after record';
        return r;
    }

    public static function parse(text:String, ?separator=",", ?escape="\"", ?endOfLine="\n"):Array<Record>
    {
        var p = new Parser(text, separator, escape, endOfLine);
        return p.records();
    }

}

