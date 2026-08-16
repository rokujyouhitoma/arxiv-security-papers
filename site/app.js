document.addEventListener('DOMContentLoaded', () => {
  let activeTag = '';
  let activePeriod = 'monthly';

  // DOM Elements
  const searchInput = document.getElementById('searchInput');
  const searchBtn = document.getElementById('searchBtn');
  const resultsGrid = document.getElementById('resultsGrid');
  const resultsCount = document.getElementById('resultsCount');
  const searchTime = document.getElementById('searchTime');
  const totalPapersCount = document.getElementById('totalPapersCount');
  
  const paperModal = document.getElementById('paperModal');
  const closeModalBtn = document.getElementById('closeModalBtn');
  const modalPaperId = document.getElementById('modalPaperId');
  const modalPaperTitle = document.getElementById('modalPaperTitle');
  const modalPaperTitleJa = document.getElementById('modalPaperTitleJa');
  const modalPaperBody = document.getElementById('modalPaperBody');
  const modalArxivLink = document.getElementById('modalArxivLink');
  const modalPdfLink = document.getElementById('modalPdfLink');

  const trendContent = document.getElementById('trendContent');
  const mcpToolSelect = document.getElementById('mcpToolSelect');
  const mcpArgsInput = document.getElementById('mcpArgsInput');
  const runMcpBtn = document.getElementById('runMcpBtn');
  const mcpOutput = document.getElementById('mcpOutput');

  // Parse URL GET Parameters (Google-style ?q=クエリ&tag=カテゴリ)
  const urlParams = new URLSearchParams(window.location.search);
  const initialQuery = urlParams.get('q') || urlParams.get('query');
  const initialTag = urlParams.get('tag') || urlParams.get('category');

  if (initialTag) {
    activeTag = initialTag;
    document.querySelectorAll('.filter-chip').forEach(c => {
      if (c.getAttribute('data-tag') === initialTag) c.classList.add('active');
      else c.classList.remove('active');
    });
  }

  // Initialize Stats & Search
  fetchStats();
  const queryToRun = initialQuery !== null ? initialQuery : "ペンテスト";
  searchInput.value = queryToRun;
  performSearch(queryToRun, false);

  // Tab Switching
  document.querySelectorAll('.nav-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.nav-btn').forEach(b => b.classList.remove('active'));
      document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));

      btn.classList.add('active');
      const tabId = btn.getAttribute('data-tab');
      document.getElementById(tabId).classList.add('active');

      if (tabId === 'trendsTab') {
        fetchTrends(activePeriod);
      }
    });
  });

  // Tag Filters
  document.querySelectorAll('.filter-chip').forEach(chip => {
    chip.addEventListener('click', () => {
      document.querySelectorAll('.filter-chip').forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      activeTag = chip.getAttribute('data-tag');
      performSearch(searchInput.value, true);
    });
  });

  // Search Events
  searchBtn.addEventListener('click', () => performSearch(searchInput.value, true));
  searchInput.addEventListener('keypress', (e) => {
    if (e.key === 'Enter') performSearch(searchInput.value, true);
  });

  // Browser Navigation History (Popstate)
  window.addEventListener('popstate', () => {
    const params = new URLSearchParams(window.location.search);
    const q = params.get('q') || '';
    const tag = params.get('tag') || '';
    activeTag = tag;
    document.querySelectorAll('.filter-chip').forEach(c => {
      if (c.getAttribute('data-tag') === tag) c.classList.add('active');
      else c.classList.remove('active');
    });
    searchInput.value = q;
    performSearch(q, false);
  });

  // Fetch System Stats
  async function fetchStats() {
    try {
      const res = await fetch('/api/stats');
      const data = await res.json();
      if (data.total_papers) {
        totalPapersCount.textContent = Number(data.total_papers).toLocaleString();
      }
    } catch (err) {
      console.warn("Stats fetch failed", err);
    }
  }

  // Perform RAG Search & Update URL
  async function performSearch(query, updateUrl = true) {
    const cleanQuery = (query === null || query === undefined) ? '' : String(query).trim();

    if (updateUrl) {
      const params = new URLSearchParams();
      if (cleanQuery) params.set('q', cleanQuery);
      if (activeTag) params.set('tag', activeTag);
      const newUrl = window.location.pathname + (params.toString() ? '?' + params.toString() : '');
      history.pushState({ q: cleanQuery, tag: activeTag }, '', newUrl);
    }

    const startTime = performance.now();
    resultsGrid.innerHTML = '<p style="color: var(--text-muted);">検索中...</p>';
    
    try {
      let url = `/api/search?q=${encodeURIComponent(cleanQuery)}&top_k=12`;
      if (activeTag) url += `&category=${encodeURIComponent(activeTag)}`;

      const res = await fetch(url);
      if (!res.ok) {
        throw new Error(`HTTP ${res.status} ${res.statusText}`);
      }
      const data = await res.json();
      const endTime = performance.now();

      const profile = data['profile'];
      if (profile && profile['total_ms'] !== undefined) {
        searchTime.textContent = `⚡ ${profile['total_ms']} ms (${profile['candidates_evaluated']}件評価 / 全${profile['total_documents']}件)`;
      } else {
        const elapsed = Math.round(endTime - startTime);
        searchTime.textContent = `${elapsed} ms で取得`;
      }

      if (data.status === 'success' && data.results) {
        renderResults(data.results);
      } else {
        resultsGrid.innerHTML = '<p class="loading-text">該当する論文は見つかりませんでした。</p>';
        resultsCount.textContent = '検索結果 (0件)';
      }
    } catch (err) {
      resultsGrid.innerHTML = `<p style="color: #ef4444;">検索エラーが発生しました: ${escapeHtml(err.message)}</p>`;
    }
  }

  // Render Paper Cards
  function renderResults(results) {
    resultsCount.textContent = `検索結果 (${results.length}件)`;
    if (results.length === 0) {
      resultsGrid.innerHTML = '<p class="loading-text">該当する論文は見つかりませんでした。</p>';
      return;
    }

    resultsGrid.innerHTML = results.map(paper => `
      <div class="glass-panel paper-card" onclick="openPaperModal('${escapeHtml(paper.id)}')">
        <div>
          <div class="card-top">
            <span class="arxiv-id-tag">arXiv: ${escapeHtml(paper.id)}</span>
            <span class="score-badge">Score: ${escapeHtml(String(paper['score']))}</span>
          </div>
          <h3 class="card-title">${escapeHtml(paper.title)}</h3>
          <p class="card-desc">${escapeHtml(paper.description || '要約情報なし')}</p>
        </div>
        <div class="card-footer">
          <div class="card-tags">
            ${(paper.tags || []).slice(0, 3).map(t => `<span class="mini-tag">${escapeHtml(t)}</span>`).join('')}
          </div>
          <span style="font-size: 0.8rem; color: var(--accent-primary);">詳細を見る &rarr;</span>
        </div>
      </div>
    `).join('');
  }

  // Modal Dialog handling (Fullscreen Viewer with Topology Network)
  window.openPaperModal = async function(arxivId) {
    paperModal.classList.remove('hidden');
    document.body.style.overflow = 'hidden';
    modalPaperId.textContent = `arXiv: ${arxivId}`;
    if (modalArxivLink) modalArxivLink.href = `https://arxiv.org/abs/${encodeURIComponent(arxivId)}`;
    if (modalPdfLink) modalPdfLink.href = `https://arxiv.org/pdf/${encodeURIComponent(arxivId)}.pdf`;

    modalPaperTitle.textContent = '読み込み中...';
    modalPaperTitleJa.textContent = '';
    modalPaperBody.innerHTML = '<p class="loading-text">OKF ドキュメントを取得中...</p>';

    try {
      const res = await fetch(`/api/paper/${encodeURIComponent(arxivId)}`);
      const data = await res.json();
      if (data.status === 'success' && data.content) {
        modalPaperTitle.textContent = data.content.match(/title:\s*"(.*?)"/)?.[1] || arxivId;
        modalPaperTitleJa.textContent = data.content.match(/title_ja:\s*"(.*?)"/)?.[1] || '';
        
        const compiled = window.MarkdownCompiler.compile(data.content);
        modalPaperBody.innerHTML = compiled.html;

        // Fetch & Render Related Papers Proximity Network
        fetchRelatedPapersTopology(arxivId, modalPaperBody);

        window.MarkdownCompiler.renderMermaid(modalPaperBody);
      }
    } catch (err) {
      modalPaperBody.innerHTML = `<p style="color:#ef4444;">取得エラー: ${escapeHtml(err.message)}</p>`;
    }
  };

  async function fetchRelatedPapersTopology(arxivId, container) {
    try {
      const res = await fetch(`/api/paper/${encodeURIComponent(arxivId)}/related`);
      const data = await res.json();
      if (data.status === 'success' && data.related_papers && data.related_papers.length > 0) {
        const section = document.createElement('div');
        section.className = 'related-papers-section';
        
        let graphHtml = '';
        if (data.mermaid_graph) {
          graphHtml = `
            <div class="related-graph-box">
              <div class="mermaid">${escapeHtml(data.mermaid_graph)}</div>
            </div>
          `;
        }

        const cardsHtml = data.related_papers.map(p => `
          <div class="related-card" onclick="openPaperModal('${escapeHtml(p['target_id'] || '')}')">
            <div class="related-card-top">
              <span class="arxiv-id-tag">arXiv: ${escapeHtml(p['target_id'] || '')}</span>
              <span class="sim-badge">類似度: ${Math.round((p['similarity'] || 0) * 100)}%</span>
            </div>
            <h4 class="related-card-title">${escapeHtml(p['title'] || p['target_id'] || '')}</h4>
            <p class="related-card-desc">${escapeHtml(p['description'] || '関連研究')}</p>
            <div class="card-tags">
              ${(p['shared_keywords'] || []).slice(0, 2).map(kw => `<span class="mini-tag">${escapeHtml(kw)}</span>`).join('')}
            </div>
          </div>
        `).join('');

        section.innerHTML = `
          <h3 class="related-section-title">🔗 関連論文トポロジーネットワーク (Connected Papers)</h3>
          <p class="related-section-desc">ベクトル距離・共通特徴語から事前計算された、もっとも関連性の高い近傍論文群です。クリックで直接閲覧できます。</p>
          ${graphHtml}
          <div class="related-grid">${cardsHtml}</div>
        `;

        container.appendChild(section);
        window.MarkdownCompiler.renderMermaid(section);
      }
    } catch (e) {
      console.warn('Could not load related papers:', e);
    }
  }

  function closeFullscreenModal() {
    paperModal.classList.add('hidden');
    document.body.style.overflow = '';
  }

  closeModalBtn.addEventListener('click', closeFullscreenModal);
  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !paperModal.classList.contains('hidden')) {
      closeFullscreenModal();
    }
  });

  // Trends Tab
  document.querySelectorAll('.period-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.period-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      activePeriod = btn.getAttribute('data-period');
      fetchTrends(activePeriod);
    });
  });

  async function fetchTrends(period) {
    trendContent.innerHTML = '<p class="loading-text">トレンドデータを取得中...</p>';
    try {
      const res = await fetch(`/api/trends?period=${encodeURIComponent(period)}`);
      const data = await res.json();
      if (data.status === 'success' && data.content) {
        const compiled = window.MarkdownCompiler.compile(data.content);
        trendContent.innerHTML = compiled.html;
        window.MarkdownCompiler.renderMermaid(trendContent);
      }
    } catch (err) {
      trendContent.innerHTML = `<p style="color:#ef4444;">トレンド取得エラー: ${escapeHtml(err.message)}</p>`;
    }
  }

  // MCP Sandbox
  mcpToolSelect.addEventListener('change', () => {
    const selected = mcpToolSelect.value;
    if (selected === 'search_security_papers') {
      mcpArgsInput.value = JSON.stringify({ query: "ペンテスト自動化", top_k: 5 }, null, 2);
    } else if (selected === 'get_paper_summary') {
      mcpArgsInput.value = JSON.stringify({ arxiv_id: "2608.12996" }, null, 2);
    } else if (selected === 'get_latest_trends') {
      mcpArgsInput.value = JSON.stringify({ period: "monthly" }, null, 2);
    } else if (selected === 'query_attack_technique') {
      mcpArgsInput.value = JSON.stringify({ technique_id: "T1059" }, null, 2);
    }
  });

  runMcpBtn.addEventListener('click', async () => {
    mcpOutput.textContent = '⚡ MCP JSON-RPC 呼び出し中...';
    try {
      const name = mcpToolSelect.value;
      const args = JSON.parse(mcpArgsInput.value);

      const res = await fetch('/api/mcp', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ name, arguments: args })
      });
      const data = await res.json();
      mcpOutput.textContent = JSON.stringify(data, null, 2);
    } catch (err) {
      mcpOutput.textContent = `エラー: ${err.message}`;
    }
  });

  function escapeHtml(str) {
    if (!str) return '';
    return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }
});
