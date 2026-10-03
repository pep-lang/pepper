# The built-in flame graph renderer: folded stacks in, an SVG out, in the
# style of Brendan Gregg's flamegraph.pl. Each frame is a box as wide as
# the share of samples it was on the stack for, above the frame that
# called it; hovering shows its numbers, and clicking zooms into it.

# The image's width and each frame's height, in pixels.
const WIDTH = 1200;
const FRAME_HEIGHT = 16;
# Room above the frames for the title, and below them for the details line.
const TOP = 36;
const BOTTOM = 28;
const SIDE = 10;
# Frames narrower than this many pixels are left out.
const MINIMUM_WIDTH = 0.1;
# The width of one character of the frames' 12-pixel font, about.
const CHARACTER_WIDTH = 7.0;

# A function in the call tree: the samples taken with it on the stack, and
# the functions it called, by name.
struct Node {
    var name: String;
    var total: long;
    var children: Map<String, Node>;

    construct(name: String) {
        this.name = name;
        this.total = 0;
        this.children = Map<String, Node>();
    }

    # The child named `name`, added when it is new.
    child(name: String): Node {
        if (!children.contains(name)) {
            children[name] = Node(name);
        }
        return children[name];
    }
}

# A node to draw, where its box starts (in samples from the left), and how
# deep in the stack it is.
struct Placed {
    var node: Node;
    var start: long;
    var depth: ulong;

    construct(node: Node, start: long, depth: ulong) {
        this.node = node;
        this.start = start;
        this.depth = depth;
    }
}

# The call tree of folded stacks: each line is a stack's names, outermost
# first, joined by `;`, then a space and its sample count. Lines that do
# not end in a count are skipped.
export build_tree(folded: String): Node {
    var root = Node("all");
    for (var line in folded.lines()) {
        var space = line.rfind(" ");
        if (space <= 0) {
            continue;
        }
        var count = long.parse(line.substr_bytes((space + 1) as ulong, line.size - (space + 1) as ulong).trim());
        if (count.is_empty() or count.value() <= 0) {
            continue;
        }
        root.total += count.value();
        var node = root;
        for (var name in line.substr_bytes(0, space as ulong).split(";")) {
            node = node.child(name);
            node.total += count.value();
        }
    }
    return root;
}

# The flame graph of `folded` as an SVG document titled `title`.
export render_svg(folded: String, title: String): String {
    var root = build_tree(folded);
    var total = root.total > 0 ? root.total : 1;
    var inner = (WIDTH - 2 * SIDE) as double;
    var scale = inner / (total as double);
    # Lay out every frame wide enough to see, without recursion: a deep
    # stack must not exhaust this program's own.
    var boxes = Array<Placed>();
    var pending = Array<Placed>();
    ulong deepest = 0;
    pending.append(Placed(root, 0, 0));
    while (!pending.is_empty) {
        var placed = pending.pop();
        if ((placed.node.total as double) * scale < MINIMUM_WIDTH) {
            continue;
        }
        boxes.append(placed);
        if (placed.depth > deepest) {
            deepest = placed.depth;
        }
        var start = placed.start;
        for (var (name, child) in placed.node.children) {
            pending.append(Placed(child, start, placed.depth + 1));
            start += child.total;
        }
    }
    var height = TOP + (deepest + 1) * FRAME_HEIGHT + BOTTOM;
    var out = StringBuilder();
    out.append("<?xml version=\"1.0\" standalone=\"no\"?>\n");
    out.append($"<svg version=\"1.1\" width=\"{WIDTH}\" height=\"{height}\" viewBox=\"0 0 {WIDTH} {height}\" ");
    out.append("xmlns=\"http://www.w3.org/2000/svg\" onload=\"init(evt)\">\n");
    out.append("<style>\n");
    out.append("text { font-family: Verdana, sans-serif; font-size: 12px; fill: #000; }\n");
    out.append("#title { font-size: 17px; text-anchor: middle; }\n");
    out.append(".frame { cursor: pointer; }\n");
    out.append(".frame:hover rect { stroke: #000; stroke-width: 0.5; }\n");
    out.append("#reset { cursor: pointer; visibility: hidden; }\n");
    out.append("</style>\n");
    out.append($"<rect x=\"0\" y=\"0\" width=\"{WIDTH}\" height=\"{height}\" fill=\"#f8f8f8\"/>\n");
    out.append($"<text id=\"title\" x=\"{WIDTH / 2}\" y=\"24\">{escape(title)}</text>\n");
    out.append("<text id=\"reset\" x=\"10\" y=\"24\">Reset zoom</text>\n");
    out.append($"<text id=\"details\" x=\"10\" y=\"{height - 10}\"> </text>\n");
    out.append($"<g id=\"frames\" data-width=\"{inner}\" data-left=\"{SIDE}\">\n");
    for (var placed in boxes) {
        var node = placed.node;
        var x = (SIDE as double) + (placed.start as double) * scale;
        var width = (node.total as double) * scale;
        var y = height - BOTTOM - (placed.depth + 1) * FRAME_HEIGHT;
        var name = escape(node.name);
        var share = percent(node.total, total);
        var noun = node.total == 1 ? "sample" : "samples";
        out.append(
            $"<g class=\"frame\" data-start=\"{placed.start}\" data-total=\"{node.total}\" data-depth=\"{placed.depth}\">"
        );
        out.append($"<title>{name} ({node.total} {noun}, {share})</title>");
        out.append(
            $"<rect x=\"{fixed(x)}\" y=\"{y}\" width=\"{fixed(width)}\" height=\"{FRAME_HEIGHT - 1}\" rx=\"2\" fill=\"{color(node.name)}\"/>"
        );
        out.append($"<text x=\"{fixed(x + 3.0)}\" y=\"{y + FRAME_HEIGHT - 4}\">{escape(fit(node.name, width))}</text>");
        out.append("</g>\n");
    }
    out.append("</g>\n");
    out.append(SCRIPT);
    out.append("</svg>\n");
    return out.to_string();
}

# The part of `name` that fits a box `width` pixels wide: all of it, its
# start and `..`, or nothing.
fit(name: String, width: double): String {
    var room = ((width - 6.0) / CHARACTER_WIDTH) as long;
    if (room < 3) {
        return "";
    }
    if ((name.size as long) <= room) {
        return name;
    }
    # Cut on a character boundary.
    ulong end = (room - 2) as ulong;
    while (end > 0 and (name.byte_at(end) & 192) == 128) {
        end -= 1;
    }
    return name.substr_bytes(0, end) + "..";
}

# `value` with one decimal, as SVG coordinates are written.
fixed(value: double): String {
    var tenths = (value * 10.0 + 0.5) as long;
    return $"{tenths / 10}.{tenths % 10}";
}

# `part` as a percentage of `whole`, with two decimals: `12.34%`.
percent(part: long, whole: long): String {
    var hundredths = (part * 10000 + whole / 2) / whole;
    var fraction = hundredths % 100;
    return $"{hundredths / 100}.{fraction < 10 ? "0" : ""}{fraction}%";
}

# A warm color for a frame, the same for the same name.
color(name: String): String {
    uint hash = 2166136261;
    for (var byte in name.bytes()) {
        hash = (hash ^ (byte as uint)).wrapping_mul(16777619);
    }
    var red = 205 + hash % 50;
    var green = (hash / 50) % 180 + 50;
    var blue = (hash / 9000) % 55;
    return $"rgb({red},{green},{blue})";
}

# `text` with the characters XML gives a meaning written as references.
escape(text: String): String {
    if (text.find("&") < 0 and text.find("<") < 0 and text.find(">") < 0 and text.find("\"") < 0) {
        return text;
    }
    return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;");
}

# Zooming: clicking a frame widens it to the whole image and hides what is
# not above or below it; "Reset zoom" undoes it. Hovering shows a frame's
# numbers on the details line.
const SCRIPT = "<script type=\"text/ecmascript\"><![CDATA[
var frames, details, reset, inner, left;
function init(evt) {
  frames = document.getElementById('frames');
  details = document.getElementById('details').firstChild;
  reset = document.getElementById('reset');
  inner = parseFloat(frames.getAttribute('data-width'));
  left = parseFloat(frames.getAttribute('data-left'));
  reset.addEventListener('click', function () { zoom(null); });
  for (var g of frames.children) {
    g.addEventListener('click', function () { zoom(this); });
    g.addEventListener('mouseover', function () { details.nodeValue = this.querySelector('title').textContent; });
    g.addEventListener('mouseout', function () { details.nodeValue = ' '; });
  }
}
function number(g, name) { return parseFloat(g.getAttribute('data-' + name)); }
function fit(name, width) {
  var room = Math.floor((width - 6) / 7);
  if (room < 3) return '';
  return name.length <= room ? name : name.substring(0, room - 2) + '..';
}
function zoom(target) {
  var root = frames.querySelector('[data-depth=\"0\"]');
  var start = target ? number(target, 'start') : 0;
  var total = target ? number(target, 'total') : number(root, 'total');
  var depth = target ? number(target, 'depth') : 0;
  reset.style.visibility = target ? 'visible' : 'hidden';
  for (var g of frames.children) {
    var s = number(g, 'start'), t = number(g, 'total'), d = number(g, 'depth');
    var inside = d >= depth ? (s >= start && s + t <= start + total) : (s <= start && s + t >= start + total);
    var rect = g.querySelector('rect'), text = g.querySelector('text');
    if (!inside) { g.style.display = 'none'; continue; }
    var x = d >= depth ? left + (s - start) / total * inner : left;
    var w = d >= depth ? t / total * inner : inner;
    g.style.display = w < 0.1 ? 'none' : '';
    rect.setAttribute('x', x);
    rect.setAttribute('width', w);
    text.setAttribute('x', x + 3);
    var title = g.querySelector('title').textContent;
    text.textContent = fit(title.substring(0, title.lastIndexOf(' (')), w);
  }
}
]]></script>
";
