class MarkdownLexer{tokenize(a){if(!a)return[];a=a.replace(/\r\n/g,"\n").split("\n");const f=[];let e=0;for(;e<a.length;){var d=a[e],h=d.trim();if(h)if(h.startsWith("```")){h=h.replace(/^```/,"").trim();d=[];for(e++;e<a.length&&!a[e].trim().startsWith("```");)d.push(a[e]),e++;e++;"mermaid"===h.toLowerCase()?f.push({type:"MERMAID",code:d.join("\n")}):f.push({type:"CODE_BLOCK",lang:h||"text",code:d.join("\n")})}else if(d=d.match(/^(#{1,6})\s+(.*)$/))f.push({type:"HEADING",level:d[1].length,content:d[2].trim()}),
e++;else if(/^(\-{3,}|\*{3,})$/.test(h))f.push({type:"HR"}),e++;else if(h.startsWith("|")&&h.endsWith("|")){for(d=[];e<a.length&&a[e].trim().startsWith("|")&&a[e].trim().endsWith("|");)d.push(a[e].trim()),e++;if(2<=d.length){const k=v=>v.split("|").slice(1,-1).map(q=>q.trim());h=k(d[0]);let m=1;d[1].includes("---")&&(m=2);d=d.slice(m).map(k);f.push({type:"TABLE",headers:h,rows:d})}}else if(/^[\-\*]\s+/.test(h)){for(h=[];e<a.length&&/^[\-\*]\s+/.test(a[e].trim());)h.push(a[e].trim().replace(/^[\-\*]\s+/,
"")),e++;f.push({type:"LIST",items:h})}else if(h.startsWith(">")){for(h=[];e<a.length&&a[e].trim().startsWith(">");)h.push(a[e].trim().replace(/^>\s?/,"")),e++;f.push({type:"BLOCKQUOTE",content:h.join(" ")})}else f.push({type:"PARAGRAPH",content:h}),e++;else e++}return f}}"undefined"!==typeof module&&module.exports&&(module.exports={MarkdownLexer});class MarkdownParser{parse(a){const f={type:"DOCUMENT",children:[]};for(const e of a)f.children.push({type:e.type,payload:e,children:[]});return f}}"undefined"!==typeof module&&module.exports&&(module.exports={MarkdownParser});class MarkdownEvaluator{constructor(){this.mermaidCount=0}evaluate(a){this.mermaidCount=0;return this._evaluateNode(a)}_evaluateNode(a){if("DOCUMENT"===a.type)return{...a,children:a.children.map(e=>this._evaluateNode(e))};if("HEADING"===a.type||"PARAGRAPH"===a.type||"BLOCKQUOTE"===a.type){var f=this._evaluateInlineText(a.payload.content||"");return{...a,evaluated:{...a.payload,content:f}}}if("TABLE"===a.type){f=a.payload.headers.map(d=>this._evaluateInlineText(d));const e=a.payload.rows.map(d=>d.map(h=>
this._evaluateInlineText(h)));return{...a,evaluated:{headers:f,rows:e}}}return"LIST"===a.type?(f=a.payload.items.map(e=>this._evaluateInlineText(e)),{...a,evaluated:{...a.payload,items:f}}):"MERMAID"===a.type?(this.mermaidCount++,f=`mermaid-diagram-${this.mermaidCount}-${Math.random().toString(36).substring(2,7)}`,{...a,evaluated:{id:f,code:a.payload.code}}):{...a,evaluated:a.payload}}_evaluateInlineText(a){if(!a)return"";a=a.replace(/\*\*(.*?)\*\*/g,"<strong>$1</strong>");a=a.replace(/`([^`]+)`/g,
'<code class="inline-code">$1</code>');return a=a.replace(/\[([^\]]+)\]\(([^)]+)\)/g,'<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>')}}"undefined"!==typeof module&&module.exports&&(module.exports={MarkdownEvaluator});class MarkdownRenderer{render(a){if(!a||"DOCUMENT"!==a.type)return{html:"",mermaidElements:[]};const f=[],e=[];for(const h of a.children){var d=h.evaluated||{};switch(h.type){case "HEADING":f.push(`<h${d.level} class="md-h${d.level}">${d.content}</h${d.level}>`);break;case "PARAGRAPH":f.push(`<p class="md-p">${d.content}</p>`);break;case "HR":f.push('<hr class="md-hr" />');break;case "BLOCKQUOTE":f.push(`<blockquote class="md-blockquote">${d.content}</blockquote>`);break;case "LIST":a=d.items.map(k=>
`<li>${k}</li>`).join("");f.push(`<ul class="md-list">${a}</ul>`);break;case "TABLE":a=d.headers.map(k=>`<th>${k}</th>`).join("");d=d.rows.map(k=>`<tr>${k.map(m=>`<td>${m}</td>`).join("")}</tr>`).join("");f.push(`
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
f)}}}window.MarkdownCompiler=new MarkdownCompilerEngine;document.addEventListener("DOMContentLoaded",()=>{async function a(b,c=!0){b=null===b||void 0===b?"":String(b).trim();c&&(c=new URLSearchParams,b&&c.set("q",b),m&&c.set("tag",m),history.pushState({q:b,tag:m},"",window.location.pathname+(c.toString()?"?"+c.toString():"")));c=performance.now();x.innerHTML='<p style="color: var(--text-muted);">\u691c\u7d22\u4e2d...</p>';try{let g=`/api/search?q=${encodeURIComponent(b)}&top_k=12`;m&&(g+=`&category=${encodeURIComponent(m)}`);const l=await fetch(g);if(!l.ok)throw Error(`HTTP ${l.status} ${l.statusText}`);
const r=await l.json(),n=performance.now(),p=r.profile;L.textContent=p&&void 0!==p.total_ms?`\u26a1 ${p.total_ms} ms (${p.candidates_evaluated}\u4ef6\u8a55\u4fa1 / \u5168${p.total_documents}\u4ef6)`:`${Math.round(n-c)} ms \u3067\u53d6\u5f97`;"success"===r.status&&r.results?f(r.results):(x.innerHTML='<p class="loading-text">\u8a72\u5f53\u3059\u308b\u8ad6\u6587\u306f\u898b\u3064\u304b\u308a\u307e\u305b\u3093\u3067\u3057\u305f\u3002</p>',D.textContent="\u691c\u7d22\u7d50\u679c (0\u4ef6)")}catch(g){x.innerHTML=
`<p style="color: #ef4444;">\u691c\u7d22\u30a8\u30e9\u30fc\u304c\u767a\u751f\u3057\u307e\u3057\u305f: ${k(g.message)}</p>`}}function f(b){D.textContent=`\u691c\u7d22\u7d50\u679c (${b.length}\u4ef6)`;x.innerHTML=0===b.length?'<p class="loading-text">\u8a72\u5f53\u3059\u308b\u8ad6\u6587\u306f\u898b\u3064\u304b\u308a\u307e\u305b\u3093\u3067\u3057\u305f\u3002</p>':b.map(c=>{var g=(c.authors||[]).slice(0,3).join(", ");g=g?`<div class="card-authors">\ud83d\udc65 \u8457\u8005: ${k(g)}</div>`:"";const l=
c.highlight?`<div class="card-snippet">${c.highlight}</div>`:`<p class="card-desc">${k(c.description||"\u8981\u7d04\u60c5\u5831\u306a\u3057")}</p>`,r=c.path?"/"+encodeURI(c.path):"#",n=c.path?"/"+encodeURI(c.path.replace("outputs/okf_papers/","raw_data/").replace(".md",".txt")):"#",p=`/preview/${encodeURIComponent(c.id)}`;return`
      <div class="glass-panel paper-card">
        <div style="cursor: pointer;" onclick="openPaperModal('${k(c.id)}')">
          <div class="card-top">
            <span class="arxiv-id-tag">arXiv: ${k(c.id)}</span>
            <span class="score-badge">Score: ${k(String(c.score))}</span>
          </div>
          <h3 class="card-title">${k(c.title)}</h3>
          ${g}
          ${l}
        </div>
        <div class="card-footer">
          <div class="card-tags">
            ${(c.tags||[]).slice(0,2).map(M=>`<span class="mini-tag">${k(M)}</span>`).join("")}
          </div>
          <div class="card-actions-row">
            <a href="${n}" target="_blank" rel="noopener" class="card-action-link" title="PDF\u5168\u6587\u30c6\u30ad\u30b9\u30c8\u62bd\u51fa\u30d5\u30a1\u30a4\u30eb (.txt)" onclick="event.stopPropagation()">\ud83d\udcdc \u751f\u30c6\u30ad\u30b9\u30c8</a>
            <a href="${r}" target="_blank" rel="noopener" class="card-action-link" title="\u751f\u306e OKF Markdown \u3092\u30d7\u30ec\u30fc\u30f3\u30c6\u30ad\u30b9\u30c8\u3067\u8868\u793a (.md)" onclick="event.stopPropagation()">\ud83d\udcdd .md</a>
            <a href="${p}" target="_blank" rel="noopener" class="card-action-link" title="\u30b9\u30bf\u30f3\u30c9\u30a2\u30ed\u30f3 HTML \u30d7\u30ec\u30d3\u30e5\u30fc" onclick="event.stopPropagation()">\ud83d\udc41\ufe0f \u30d7\u30ec\u30d3\u30e5\u30fc \u2197</a>
            <button class="card-action-btn" onclick="openPaperModal('${k(c.id)}')">\u8a73\u7d30 &rarr;</button>
          </div>
        </div>
      </div>
      `}).join("")}async function e(b,c){try{const g=await (await fetch(`/api/paper/${encodeURIComponent(b)}/related`)).json();if("success"===g.status&&g.related_papers&&0<g.related_papers.length){const l=document.createElement("div");l.className="related-papers-section";b="";g.mermaid_graph&&(b=`
            <div class="related-graph-box">
              <div class="mermaid">${k(g.mermaid_graph)}</div>
            </div>
          `);const r=g.related_papers.map(n=>`
          <div class="related-card" onclick="openPaperModal('${k(n.target_id||"")}')">
            <div class="related-card-top">
              <span class="arxiv-id-tag">arXiv: ${k(n.target_id||"")}</span>
              <span class="sim-badge">\u985e\u4f3c\u5ea6: ${Math.round(100*(n.similarity||0))}%</span>
            </div>
            <h4 class="related-card-title">${k(n.title||n.target_id||"")}</h4>
            <p class="related-card-desc">${k(n.description||"\u95a2\u9023\u7814\u7a76")}</p>
            <div class="card-tags">
              ${(n.shared_keywords||[]).slice(0,2).map(p=>`<span class="mini-tag">${k(p)}</span>`).join("")}
            </div>
          </div>
        `).join("");l.innerHTML=`
          <h3 class="related-section-title">\ud83d\udd17 \u95a2\u9023\u8ad6\u6587\u30c8\u30dd\u30ed\u30b8\u30fc\u30cd\u30c3\u30c8\u30ef\u30fc\u30af (Connected Papers)</h3>
          <p class="related-section-desc">\u30d9\u30af\u30c8\u30eb\u8ddd\u96e2\u30fb\u5171\u901a\u7279\u5fb4\u8a9e\u304b\u3089\u4e8b\u524d\u8a08\u7b97\u3055\u308c\u305f\u3001\u3082\u3063\u3068\u3082\u95a2\u9023\u6027\u306e\u9ad8\u3044\u8fd1\u508d\u8ad6\u6587\u7fa4\u3067\u3059\u3002\u30af\u30ea\u30c3\u30af\u3067\u76f4\u63a5\u95b2\u89a7\u3067\u304d\u307e\u3059\u3002</p>
          ${b}
          <div class="related-grid">${r}</div>
        `;c.appendChild(l);window.MarkdownCompiler.renderMermaid(l)}}catch(g){console.warn("Could not load related papers:",g)}}function d(){z.classList.add("hidden");document.body.style.overflow=""}async function h(b){y.innerHTML='<p class="loading-text">\u30c8\u30ec\u30f3\u30c9\u30c7\u30fc\u30bf\u3092\u53d6\u5f97\u4e2d...</p>';try{const c=await (await fetch(`/api/trends?period=${encodeURIComponent(b)}`)).json();if("success"===c.status&&c.content){const g=window.MarkdownCompiler.compile(c.content);
y.innerHTML=g.html;window.MarkdownCompiler.renderMermaid(y)}}catch(c){y.innerHTML=`<p style="color:#ef4444;">\u30c8\u30ec\u30f3\u30c9\u53d6\u5f97\u30a8\u30e9\u30fc: ${k(c.message)}</p>`}}function k(b){return b?b.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;"):""}let m="",v="monthly";const q=document.getElementById("searchInput"),N=document.getElementById("searchBtn"),x=document.getElementById("resultsGrid"),D=document.getElementById("resultsCount"),L=document.getElementById("searchTime"),
O=document.getElementById("totalPapersCount"),z=document.getElementById("paperModal"),P=document.getElementById("closeModalBtn"),Q=document.getElementById("modalPaperId"),E=document.getElementById("modalPaperTitle"),F=document.getElementById("modalPaperTitleJa"),w=document.getElementById("modalPaperBody"),G=document.getElementById("modalArxivLink"),H=document.getElementById("modalPdfLink"),I=document.getElementById("modalTxtLink"),J=document.getElementById("modalOkfLink"),y=document.getElementById("trendContent"),
A=document.getElementById("mcpToolSelect"),t=document.getElementById("mcpArgsInput"),R=document.getElementById("runMcpBtn"),B=document.getElementById("mcpOutput");var u=new URLSearchParams(window.location.search);const K=u.get("q")||u.get("query"),C=u.get("tag")||u.get("category");C&&(m=C,document.querySelectorAll(".filter-chip").forEach(b=>{b.getAttribute("data-tag")===C?b.classList.add("active"):b.classList.remove("active")}));(async function(){try{const b=await (await fetch("/api/stats")).json();
b.total_papers&&(O.textContent=Number(b.total_papers).toLocaleString())}catch(b){console.warn("Stats fetch failed",b)}})();u=null!==K?K:"\u30da\u30f3\u30c6\u30b9\u30c8";q.value=u;a(u,!1);document.querySelectorAll(".nav-btn").forEach(b=>{b.addEventListener("click",()=>{document.querySelectorAll(".nav-btn").forEach(g=>g.classList.remove("active"));document.querySelectorAll(".tab-content").forEach(g=>g.classList.remove("active"));b.classList.add("active");const c=b.getAttribute("data-tab");document.getElementById(c).classList.add("active");
"trendsTab"===c&&h(v)})});document.querySelectorAll(".filter-chip").forEach(b=>{b.addEventListener("click",()=>{document.querySelectorAll(".filter-chip").forEach(c=>c.classList.remove("active"));b.classList.add("active");m=b.getAttribute("data-tag");a(q.value,!0)})});N.addEventListener("click",()=>a(q.value,!0));q.addEventListener("keypress",b=>{"Enter"===b.key&&a(q.value,!0)});window.addEventListener("popstate",()=>{const b=new URLSearchParams(window.location.search),c=b.get("q")||"",g=b.get("tag")||
"";m=g;document.querySelectorAll(".filter-chip").forEach(l=>{l.getAttribute("data-tag")===g?l.classList.add("active"):l.classList.remove("active")});q.value=c;a(c,!1)});window.openPaperModal=async function(b){z.classList.remove("hidden");document.body.style.overflow="hidden";Q.textContent=`arXiv: ${b}`;G&&(G.href=`https://arxiv.org/abs/${encodeURIComponent(b)}`);H&&(H.href=`https://arxiv.org/pdf/${encodeURIComponent(b)}.pdf`);E.textContent="\u8aad\u307f\u8fbc\u307f\u4e2d...";F.textContent="";w.innerHTML=
'<p class="loading-text">OKF \u30c9\u30ad\u30e5\u30e1\u30f3\u30c8\u3092\u53d6\u5f97\u4e2d...</p>';try{const c=await (await fetch(`/api/paper/${encodeURIComponent(b)}`)).json();if("success"===c.status&&c.content){J&&c.path&&(J.href="/"+encodeURI(c.path));I&&c.path&&(I.href="/"+encodeURI(c.path.replace("outputs/okf_papers/","raw_data/").replace(".md",".txt")));E.textContent=c.content.match(/title:\s*"(.*?)"/)?.[1]||b;F.textContent=c.content.match(/title_ja:\s*"(.*?)"/)?.[1]||"";const g=window.MarkdownCompiler.compile(c.content);
w.innerHTML=g.html;e(b,w);window.MarkdownCompiler.renderMermaid(w)}}catch(c){w.innerHTML=`<p style="color:#ef4444;">\u53d6\u5f97\u30a8\u30e9\u30fc: ${k(c.message)}</p>`}};P.addEventListener("click",d);window.addEventListener("keydown",b=>{"Escape"!==b.key||z.classList.contains("hidden")||d()});document.querySelectorAll(".period-btn").forEach(b=>{b.addEventListener("click",()=>{document.querySelectorAll(".period-btn").forEach(c=>c.classList.remove("active"));b.classList.add("active");v=b.getAttribute("data-period");
h(v)})});A.addEventListener("change",()=>{const b=A.value;"search_security_papers"===b?t.value=JSON.stringify({query:"\u30da\u30f3\u30c6\u30b9\u30c8\u81ea\u52d5\u5316",top_k:5},null,2):"verify_code_security"===b?t.value=JSON.stringify({code_snippet:"def login(user, pwd):\n    query = f\"SELECT * FROM users WHERE u='{user}' AND p='{pwd}'\"\n    cursor.execute(query)",language:"python"},null,2):"get_cwe_mitigation_recipe"===b?t.value=JSON.stringify({cwe_id:"CWE-89"},null,2):"get_related_papers_graph"===
b?t.value=JSON.stringify({arxiv_id:"2502.16730"},null,2):"get_paper_summary"===b?t.value=JSON.stringify({arxiv_id:"2502.16730"},null,2):"get_latest_trends"===b?t.value=JSON.stringify({period:"monthly"},null,2):"query_attack_technique"===b&&(t.value=JSON.stringify({technique_id:"T1059"},null,2))});R.addEventListener("click",async()=>{B.textContent="\u26a1 MCP JSON-RPC \u547c\u3073\u51fa\u3057\u4e2d...";try{const b=A.value,c=JSON.parse(t.value),g=await (await fetch("/api/mcp",{method:"POST",headers:{"Content-Type":"application/json"},
body:JSON.stringify({name:b,arguments:c})})).json();B.textContent=JSON.stringify(g,null,2)}catch(b){B.textContent=`\u30a8\u30e9\u30fc: ${b.message}`}})});
