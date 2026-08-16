class MarkdownLexer{tokenize(a){if(!a)return[];a=a.replace(/\r\n/g,"\n").split("\n");const f=[];let e=0;for(;e<a.length;){var d=a[e],g=d.trim();if(g)if(g.startsWith("```")){g=g.replace(/^```/,"").trim();d=[];for(e++;e<a.length&&!a[e].trim().startsWith("```");)d.push(a[e]),e++;e++;"mermaid"===g.toLowerCase()?f.push({type:"MERMAID",code:d.join("\n")}):f.push({type:"CODE_BLOCK",lang:g||"text",code:d.join("\n")})}else if(d=d.match(/^(#{1,6})\s+(.*)$/))f.push({type:"HEADING",level:d[1].length,content:d[2].trim()}),
e++;else if(/^(\-{3,}|\*{3,})$/.test(g))f.push({type:"HR"}),e++;else if(g.startsWith("|")&&g.endsWith("|")){for(d=[];e<a.length&&a[e].trim().startsWith("|")&&a[e].trim().endsWith("|");)d.push(a[e].trim()),e++;if(2<=d.length){const k=u=>u.split("|").slice(1,-1).map(p=>p.trim());g=k(d[0]);let l=1;d[1].includes("---")&&(l=2);d=d.slice(l).map(k);f.push({type:"TABLE",headers:g,rows:d})}}else if(/^[\-\*]\s+/.test(g)){for(g=[];e<a.length&&/^[\-\*]\s+/.test(a[e].trim());)g.push(a[e].trim().replace(/^[\-\*]\s+/,
"")),e++;f.push({type:"LIST",items:g})}else if(g.startsWith(">")){for(g=[];e<a.length&&a[e].trim().startsWith(">");)g.push(a[e].trim().replace(/^>\s?/,"")),e++;f.push({type:"BLOCKQUOTE",content:g.join(" ")})}else f.push({type:"PARAGRAPH",content:g}),e++;else e++}return f}}"undefined"!==typeof module&&module.exports&&(module.exports={MarkdownLexer});class MarkdownParser{parse(a){const f={type:"DOCUMENT",children:[]};for(const e of a)f.children.push({type:e.type,payload:e,children:[]});return f}}"undefined"!==typeof module&&module.exports&&(module.exports={MarkdownParser});class MarkdownEvaluator{constructor(){this.mermaidCount=0}evaluate(a){this.mermaidCount=0;return this._evaluateNode(a)}_evaluateNode(a){if("DOCUMENT"===a.type)return{...a,children:a.children.map(e=>this._evaluateNode(e))};if("HEADING"===a.type||"PARAGRAPH"===a.type||"BLOCKQUOTE"===a.type){var f=this._evaluateInlineText(a.payload.content||"");return{...a,evaluated:{...a.payload,content:f}}}if("TABLE"===a.type){f=a.payload.headers.map(d=>this._evaluateInlineText(d));const e=a.payload.rows.map(d=>d.map(g=>
this._evaluateInlineText(g)));return{...a,evaluated:{headers:f,rows:e}}}return"LIST"===a.type?(f=a.payload.items.map(e=>this._evaluateInlineText(e)),{...a,evaluated:{items:f}}):"MERMAID"===a.type?(this.mermaidCount++,{...a,evaluated:{code:a.payload.code,elementId:`mermaid-diagram-${this.mermaidCount}-${Date.now()}`}}):{...a,evaluated:a.payload}}_evaluateInlineText(a){if(!a)return"";a=a.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");a=a.replace(/\*\*(.*?)\*\*/g,'<strong class="md-bold">$1</strong>');
a=a.replace(/`(.*?)`/g,'<code class="md-inline-code">$1</code>');return a=a.replace(/\[(.*?)\]\((.*?)\)/g,'<a href="$2" class="md-link" target="_blank" rel="noopener">$1</a>')}}"undefined"!==typeof module&&module.exports&&(module.exports={MarkdownEvaluator});class MarkdownRenderer{render(a){if(!a||"DOCUMENT"!==a.type)return"";const f=[],e=[];for(const g of a.children){var d=g.evaluated||{};switch(g.type){case "HEADING":f.push(`<h${d.level} class="md-h${d.level}">${d.content}</h${d.level}>`);break;case "PARAGRAPH":f.push(`<p class="md-p">${d.content}</p>`);break;case "HR":f.push('<hr class="md-hr" />');break;case "BLOCKQUOTE":f.push(`<blockquote class="md-blockquote">${d.content}</blockquote>`);break;case "LIST":a=d.items.map(k=>`<li>${k}</li>`).join("");
f.push(`<ul class="md-list">${a}</ul>`);break;case "TABLE":a=d.headers.map(k=>`<th>${k}</th>`).join("");d=d.rows.map(k=>`<tr>${k.map(l=>`<td>${l}</td>`).join("")}</tr>`).join("");f.push(`
            <div class="md-table-wrapper">
              <table class="md-table">
                <thead><tr>${a}</tr></thead>
                <tbody>${d}</tbody>
              </table>
            </div>
          `);break;case "MERMAID":e.push(d);f.push(`
            <div class="md-mermaid-wrapper">
              <div class="mermaid" id="${d.elementId}">
${d.code}
              </div>
            </div>
          `);break;case "CODE_BLOCK":f.push(`
            <pre class="md-code-block"><code class="language-${d.lang}">${d.code}</code></pre>
          `)}}return{html:f.join("\n"),mermaidElements:e}}}"undefined"!==typeof module&&module.exports&&(module.exports={MarkdownRenderer});class MarkdownCompilerEngine{constructor(){this.lexer=new MarkdownLexer;this.parser=new MarkdownParser;this.evaluator=new MarkdownEvaluator;this.renderer=new MarkdownRenderer}compile(a){a=this.lexer.tokenize(a);a=this.parser.parse(a);a=this.evaluator.evaluate(a);return this.renderer.render(a)}async renderMermaid(a){if("undefined"!==typeof mermaid&&a)try{mermaid.initialize({startOnLoad:!1,theme:"dark",securityLevel:"loose"}),await mermaid.run({nodes:a.querySelectorAll(".mermaid")})}catch(f){console.warn("Mermaid rendering warning:",
f)}}}window.MarkdownCompiler=new MarkdownCompilerEngine;document.addEventListener("DOMContentLoaded",()=>{async function a(b,c=!0){b=null===b||void 0===b?"":String(b).trim();c&&(c=new URLSearchParams,b&&c.set("q",b),l&&c.set("tag",l),history.pushState({q:b,tag:l},"",window.location.pathname+(c.toString()?"?"+c.toString():"")));c=performance.now();x.innerHTML='<p style="color: var(--text-muted);">\u691c\u7d22\u4e2d...</p>';try{let h=`/api/search?q=${encodeURIComponent(b)}&top_k=12`;l&&(h+=`&category=${encodeURIComponent(l)}`);const m=await fetch(h);if(!m.ok)throw Error(`HTTP ${m.status} ${m.statusText}`);
const t=await m.json(),n=performance.now(),q=t.profile;J.textContent=q&&void 0!==q.total_ms?`\u26a1 ${q.total_ms} ms (${q.candidates_evaluated}\u4ef6\u8a55\u4fa1 / \u5168${q.total_documents}\u4ef6)`:`${Math.round(n-c)} ms \u3067\u53d6\u5f97`;"success"===t.status&&t.results?f(t.results):(x.innerHTML='<p class="loading-text">\u8a72\u5f53\u3059\u308b\u8ad6\u6587\u306f\u898b\u3064\u304b\u308a\u307e\u305b\u3093\u3067\u3057\u305f\u3002</p>',D.textContent="\u691c\u7d22\u7d50\u679c (0\u4ef6)")}catch(h){x.innerHTML=
`<p style="color: #ef4444;">\u691c\u7d22\u30a8\u30e9\u30fc\u304c\u767a\u751f\u3057\u307e\u3057\u305f: ${k(h.message)}</p>`}}function f(b){D.textContent=`\u691c\u7d22\u7d50\u679c (${b.length}\u4ef6)`;x.innerHTML=0===b.length?'<p class="loading-text">\u8a72\u5f53\u3059\u308b\u8ad6\u6587\u306f\u898b\u3064\u304b\u308a\u307e\u305b\u3093\u3067\u3057\u305f\u3002</p>':b.map(c=>`
      <div class="glass-panel paper-card" onclick="openPaperModal('${k(c.id)}')">
        <div>
          <div class="card-top">
            <span class="arxiv-id-tag">arXiv: ${k(c.id)}</span>
            <span class="score-badge">Score: ${k(String(c.score))}</span>
          </div>
          <h3 class="card-title">${k(c.title)}</h3>
          <p class="card-desc">${k(c.description||"\u8981\u7d04\u60c5\u5831\u306a\u3057")}</p>
        </div>
        <div class="card-footer">
          <div class="card-tags">
            ${(c.tags||[]).slice(0,3).map(h=>`<span class="mini-tag">${k(h)}</span>`).join("")}
          </div>
          <span style="font-size: 0.8rem; color: var(--accent-primary);">\u8a73\u7d30\u3092\u898b\u308b &rarr;</span>
        </div>
      </div>
    `).join("")}async function e(b,c){try{const h=await (await fetch(`/api/paper/${encodeURIComponent(b)}/related`)).json();if("success"===h.status&&h.related_papers&&0<h.related_papers.length){const m=document.createElement("div");m.className="related-papers-section";b="";h.mermaid_graph&&(b=`
            <div class="related-graph-box">
              <div class="mermaid">${k(h.mermaid_graph)}</div>
            </div>
          `);const t=h.related_papers.map(n=>`
          <div class="related-card" onclick="openPaperModal('${k(n.target_id||"")}')">
            <div class="related-card-top">
              <span class="arxiv-id-tag">arXiv: ${k(n.target_id||"")}</span>
              <span class="sim-badge">\u985e\u4f3c\u5ea6: ${Math.round(100*(n.similarity||0))}%</span>
            </div>
            <h4 class="related-card-title">${k(n.title||n.target_id||"")}</h4>
            <p class="related-card-desc">${k(n.description||"\u95a2\u9023\u7814\u7a76")}</p>
            <div class="card-tags">
              ${(n.shared_keywords||[]).slice(0,2).map(q=>`<span class="mini-tag">${k(q)}</span>`).join("")}
            </div>
          </div>
        `).join("");m.innerHTML=`
          <h3 class="related-section-title">\ud83d\udd17 \u95a2\u9023\u8ad6\u6587\u30c8\u30dd\u30ed\u30b8\u30fc\u30cd\u30c3\u30c8\u30ef\u30fc\u30af (Connected Papers)</h3>
          <p class="related-section-desc">\u30d9\u30af\u30c8\u30eb\u8ddd\u96e2\u30fb\u5171\u901a\u7279\u5fb4\u8a9e\u304b\u3089\u4e8b\u524d\u8a08\u7b97\u3055\u308c\u305f\u3001\u3082\u3063\u3068\u3082\u95a2\u9023\u6027\u306e\u9ad8\u3044\u8fd1\u508d\u8ad6\u6587\u7fa4\u3067\u3059\u3002\u30af\u30ea\u30c3\u30af\u3067\u76f4\u63a5\u95b2\u89a7\u3067\u304d\u307e\u3059\u3002</p>
          ${b}
          <div class="related-grid">${t}</div>
        `;c.appendChild(m);window.MarkdownCompiler.renderMermaid(m)}}catch(h){console.warn("Could not load related papers:",h)}}function d(){z.classList.add("hidden");document.body.style.overflow=""}async function g(b){y.innerHTML='<p class="loading-text">\u30c8\u30ec\u30f3\u30c9\u30c7\u30fc\u30bf\u3092\u53d6\u5f97\u4e2d...</p>';try{const c=await (await fetch(`/api/trends?period=${encodeURIComponent(b)}`)).json();if("success"===c.status&&c.content){const h=window.MarkdownCompiler.compile(c.content);
y.innerHTML=h.html;window.MarkdownCompiler.renderMermaid(y)}}catch(c){y.innerHTML=`<p style="color:#ef4444;">\u30c8\u30ec\u30f3\u30c9\u53d6\u5f97\u30a8\u30e9\u30fc: ${k(c.message)}</p>`}}function k(b){return b?b.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;"):""}let l="",u="monthly";const p=document.getElementById("searchInput"),K=document.getElementById("searchBtn"),x=document.getElementById("resultsGrid"),D=document.getElementById("resultsCount"),J=document.getElementById("searchTime"),
L=document.getElementById("totalPapersCount"),z=document.getElementById("paperModal"),M=document.getElementById("closeModalBtn"),N=document.getElementById("modalPaperId"),E=document.getElementById("modalPaperTitle"),F=document.getElementById("modalPaperTitleJa"),v=document.getElementById("modalPaperBody"),G=document.getElementById("modalArxivLink"),H=document.getElementById("modalPdfLink"),y=document.getElementById("trendContent"),A=document.getElementById("mcpToolSelect"),w=document.getElementById("mcpArgsInput"),
O=document.getElementById("runMcpBtn"),B=document.getElementById("mcpOutput");var r=new URLSearchParams(window.location.search);const I=r.get("q")||r.get("query"),C=r.get("tag")||r.get("category");C&&(l=C,document.querySelectorAll(".filter-chip").forEach(b=>{b.getAttribute("data-tag")===C?b.classList.add("active"):b.classList.remove("active")}));(async function(){try{const b=await (await fetch("/api/stats")).json();b.total_papers&&(L.textContent=Number(b.total_papers).toLocaleString())}catch(b){console.warn("Stats fetch failed",
b)}})();r=null!==I?I:"\u30da\u30f3\u30c6\u30b9\u30c8";p.value=r;a(r,!1);document.querySelectorAll(".nav-btn").forEach(b=>{b.addEventListener("click",()=>{document.querySelectorAll(".nav-btn").forEach(h=>h.classList.remove("active"));document.querySelectorAll(".tab-content").forEach(h=>h.classList.remove("active"));b.classList.add("active");const c=b.getAttribute("data-tab");document.getElementById(c).classList.add("active");"trendsTab"===c&&g(u)})});document.querySelectorAll(".filter-chip").forEach(b=>
{b.addEventListener("click",()=>{document.querySelectorAll(".filter-chip").forEach(c=>c.classList.remove("active"));b.classList.add("active");l=b.getAttribute("data-tag");a(p.value,!0)})});K.addEventListener("click",()=>a(p.value,!0));p.addEventListener("keypress",b=>{"Enter"===b.key&&a(p.value,!0)});window.addEventListener("popstate",()=>{const b=new URLSearchParams(window.location.search),c=b.get("q")||"",h=b.get("tag")||"";l=h;document.querySelectorAll(".filter-chip").forEach(m=>{m.getAttribute("data-tag")===
h?m.classList.add("active"):m.classList.remove("active")});p.value=c;a(c,!1)});window.openPaperModal=async function(b){z.classList.remove("hidden");document.body.style.overflow="hidden";N.textContent=`arXiv: ${b}`;G&&(G.href=`https://arxiv.org/abs/${encodeURIComponent(b)}`);H&&(H.href=`https://arxiv.org/pdf/${encodeURIComponent(b)}.pdf`);E.textContent="\u8aad\u307f\u8fbc\u307f\u4e2d...";F.textContent="";v.innerHTML='<p class="loading-text">OKF \u30c9\u30ad\u30e5\u30e1\u30f3\u30c8\u3092\u53d6\u5f97\u4e2d...</p>';
try{const c=await (await fetch(`/api/paper/${encodeURIComponent(b)}`)).json();if("success"===c.status&&c.content){E.textContent=c.content.match(/title:\s*"(.*?)"/)?.[1]||b;F.textContent=c.content.match(/title_ja:\s*"(.*?)"/)?.[1]||"";const h=window.MarkdownCompiler.compile(c.content);v.innerHTML=h.html;e(b,v);window.MarkdownCompiler.renderMermaid(v)}}catch(c){v.innerHTML=`<p style="color:#ef4444;">\u53d6\u5f97\u30a8\u30e9\u30fc: ${k(c.message)}</p>`}};M.addEventListener("click",d);window.addEventListener("keydown",
b=>{"Escape"!==b.key||z.classList.contains("hidden")||d()});document.querySelectorAll(".period-btn").forEach(b=>{b.addEventListener("click",()=>{document.querySelectorAll(".period-btn").forEach(c=>c.classList.remove("active"));b.classList.add("active");u=b.getAttribute("data-period");g(u)})});A.addEventListener("change",()=>{const b=A.value;"search_security_papers"===b?w.value=JSON.stringify({query:"\u30da\u30f3\u30c6\u30b9\u30c8\u81ea\u52d5\u5316",top_k:5},null,2):"get_paper_summary"===b?w.value=
JSON.stringify({arxiv_id:"2608.12996"},null,2):"get_latest_trends"===b?w.value=JSON.stringify({period:"monthly"},null,2):"query_attack_technique"===b&&(w.value=JSON.stringify({technique_id:"T1059"},null,2))});O.addEventListener("click",async()=>{B.textContent="\u26a1 MCP JSON-RPC \u547c\u3073\u51fa\u3057\u4e2d...";try{const b=A.value,c=JSON.parse(w.value),h=await (await fetch("/api/mcp",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({name:b,arguments:c})})).json();
B.textContent=JSON.stringify(h,null,2)}catch(b){B.textContent=`\u30a8\u30e9\u30fc: ${b.message}`}})});
