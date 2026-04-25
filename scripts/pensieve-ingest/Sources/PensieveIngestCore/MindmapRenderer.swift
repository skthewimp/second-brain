import Foundation

public enum MindmapRenderer {
    public static func render(state: MindmapState, insights: [Insight]) -> String {
        let encoder = JSONEncoder()
        let dataJSON = (try? encoder.encode(state.root))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        let insightJSON = (try? encoder.encode(insights))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        return template
            .replacingOccurrences(of: "{{DATA}}", with: dataJSON)
            .replacingOccurrences(of: "{{INSIGHTS}}", with: insightJSON)
            .replacingOccurrences(of: "{{UPDATED}}", with: state.lastUpdated)
    }

    private static let template = #"""
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <title>Pensieve — Mindmap</title>
      <script src="https://d3js.org/d3.v7.min.js"></script>
      <style>
        :root { font-family: -apple-system, system-ui, sans-serif; }
        body { margin:0; display:grid; grid-template-columns:1fr 320px; height:100vh; background:#fafafa; }
        #chart { position:relative; }
        svg { width:100%; height:100%; cursor:grab; }
        svg:active { cursor:grabbing; }
        aside { border-left:1px solid #ddd; padding:20px; overflow-y:auto; background:#fff; }
        h2 { margin:0 0 12px; font-size:14px; text-transform:uppercase; color:#666; letter-spacing:0.5px; }
        .insight { padding:10px 12px; margin-bottom:8px; border-radius:6px; border:1px solid #eee; cursor:pointer; font-size:13px; }
        .insight:hover { background:#f5f5f5; }
        .insight .k { display:inline-block; padding:2px 6px; border-radius:3px; font-size:10px; text-transform:uppercase; margin-right:6px; font-weight:600; }
        .k.tooDeep { background:#ffe5e5; color:#c00; }
        .k.shouldGoDeeper { background:#e5efff; color:#06c; }
        .k.tooShallow { background:#fff4d4; color:#a60; }
        .k.tooBroad { background:#eaeaea; color:#444; }
        .node circle { stroke:#333; stroke-width:1px; cursor:pointer; }
        .node text { font-size:11px; fill:#222; pointer-events:none; }
        .link { fill:none; stroke:#aaa; stroke-width:1px; }
        .updated { position:absolute; bottom:8px; left:12px; font-size:11px; color:#999; }
      </style>
    </head>
    <body>
      <div id="chart">
        <svg viewBox="-500 -500 1000 1000"></svg>
        <div class="updated">Last updated {{UPDATED}}</div>
      </div>
      <aside>
        <h2>Insights</h2>
        <div id="insights"></div>
      </aside>
      <script>
        const data = {{DATA}};
        const insights = {{INSIGHTS}};

        // ---- color: importance vs noteCount mismatch ----
        const colorFor = (d) => {
          const n = d.data.noteCount, imp = d.data.importance;
          const expected = imp * 3;        // rough scale: each importance point ~ 3 notes
          const ratio = n / Math.max(1, expected);
          if (ratio > 1.5) return "#e88";  // over-explored
          if (ratio < 0.5 && imp >= 6) return "#88e"; // under-explored important
          return "#bbb";
        };
        const sizeFor = (d) => 4 + Math.sqrt(d.data.noteCount) * 3;

        // ---- radial tree layout ----
        const root = d3.hierarchy(data);
        const tree = d3.tree().size([2 * Math.PI, 380]).separation((a, b) => (a.parent === b.parent ? 1 : 2) / a.depth);
        tree(root);

        const svg = d3.select("svg");
        const g = svg.append("g");

        const linkGen = d3.linkRadial().angle(d => d.x).radius(d => d.y);
        g.append("g").selectAll("path")
          .data(root.links()).enter().append("path")
          .attr("class", "link").attr("d", linkGen);

        const node = g.append("g").selectAll("g")
          .data(root.descendants()).enter().append("g")
          .attr("class", "node")
          .attr("transform", d => `rotate(${d.x * 180 / Math.PI - 90}) translate(${d.y},0)`);

        node.append("circle")
          .attr("r", sizeFor)
          .attr("fill", colorFor)
          .on("click", (e, d) => {
            const page = d.data.sourcePages && d.data.sourcePages[0];
            if (page) {
              window.location.href = "obsidian://open?vault=SecondBrain&file=" + encodeURIComponent(page);
            }
          })
          .append("title").text(d => `${d.data.label}\n${d.data.summary}\nnotes: ${d.data.noteCount}, importance: ${d.data.importance}`);

        node.append("text")
          .attr("dy", "0.31em")
          .attr("x", d => d.x < Math.PI ? 10 : -10)
          .attr("text-anchor", d => d.x < Math.PI ? "start" : "end")
          .attr("transform", d => d.x >= Math.PI ? "rotate(180)" : null)
          .text(d => d.data.label);

        // ---- pan + zoom ----
        svg.call(d3.zoom().on("zoom", (e) => g.attr("transform", e.transform)));

        // ---- sidebar insights ----
        const list = d3.select("#insights");
        if (insights.length === 0) {
          list.append("div").attr("class", "insight").text("No insights this run.");
        } else {
          for (const i of insights) {
            const row = list.append("div").attr("class", "insight").on("click", () => {
              const target = root.descendants().find(d => d.data.id === i.nodeId);
              if (!target) return;
              const k = 2.5;
              const x = -Math.cos(target.x - Math.PI / 2) * target.y * k;
              const y = -Math.sin(target.x - Math.PI / 2) * target.y * k;
              svg.transition().duration(600).call(
                d3.zoom().transform, d3.zoomIdentity.translate(x, y).scale(k)
              );
            });
            row.append("span").attr("class", "k " + i.kind).text(i.kind);
            row.append("span").text(i.message);
          }
        }
      </script>
    </body>
    </html>
    """#
}
