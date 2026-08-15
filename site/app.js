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
    if (updateUrl) {
      const params = new URLSearchParams();
      if (query) params.set('q', query);
      if (activeTag) params.set('tag', activeTag);
      const newUrl = window.location.pathname + (params.toString() ? '?' + params.toString() : '');
      history.pushState({ q: query, tag: activeTag }, '', newUrl);
    }

    const startTime = performance.now();
    resultsGrid.innerHTML = '<p style="color: var(--text-muted);">検索中...</p>';
    
    try {
      let url = `/api/search?q=${encodeURIComponent(query)}&top_k=12`;
      if (activeTag) url += `&category=${encodeURIComponent(activeTag)}`;

      const res = await fetch(url);
      const data = await res.json();
      const endTime = performance.now();

      const elapsed = ((endTime - startTime) / 1000).toFixed(2);
      searchTime.textContent = `${elapsed} 秒で取得`;

      if (data.status === 'success' && data.results) {
        renderResults(data.results);
      } else {
        resultsGrid.innerHTML = '<p class="loading-text">該当する論文は見つかりませんでした。</p>';
        resultsCount.textContent = '検索結果 (0件)';
      }
    } catch (err) {
      resultsGrid.innerHTML = `<p style="color: #ef4444;">検索エラーが発生しました: ${err.message}</p>`;
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
      <div class="glass-panel paper-card" onclick="openPaperModal('${paper.id}')">
        <div>
          <div class="card-top">
            <span class="arxiv-id-tag">arXiv: ${paper.id}</span>
            <span class="score-badge">Score: ${paper.score}</span>
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

  // Modal Dialog handling
  window.openPaperModal = async function(arxivId) {
    paperModal.classList.remove('hidden');
    modalPaperId.textContent = `arXiv: ${arxivId}`;
    modalPaperTitle.textContent = '読み込み中...';
    modalPaperTitleJa.textContent = '';
    modalPaperBody.innerHTML = '<p>OKF ドキュメントを取得中...</p>';

    try {
      const res = await fetch(`/api/paper/${encodeURIComponent(arxivId)}`);
      const data = await res.json();
      if (data.status === 'success' && data.content) {
        modalPaperTitle.textContent = data.content.match(/title:\s*"(.*?)"/)?.[1] || arxivId;
        modalPaperTitleJa.textContent = data.content.match(/title_ja:\s*"(.*?)"/)?.[1] || '';
        
        let bodyHtml = escapeHtml(data.content)
          .replace(/# (.*?)\n/g, '<h2 style="font-family: var(--font-heading); color:#fff; margin-top:1.5rem;">$1</h2>')
          .replace(/## (.*?)\n/g, '<h3 style="color:var(--accent-secondary); margin-top:1rem;">$1</h3>')
          .replace(/### (.*?)\n/g, '<h4 style="color:#fff; margin-top:0.75rem;">$1</h4>')
          .replace(/\n\n/g, '<br/><br/>');
        modalPaperBody.innerHTML = bodyHtml;
      }
    } catch (err) {
      modalPaperBody.innerHTML = `<p style="color:#ef4444;">取得エラー: ${err.message}</p>`;
    }
  };

  closeModalBtn.addEventListener('click', () => paperModal.classList.add('hidden'));
  paperModal.addEventListener('click', (e) => {
    if (e.target === paperModal) paperModal.classList.add('hidden');
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
      const res = await fetch(`/api/trends?period=${period}`);
      const data = await res.json();
      if (data.status === 'success' && data.content) {
        let html = escapeHtml(data.content)
          .replace(/# (.*?)\n/g, '<h1 style="color:#fff; font-family:var(--font-heading); margin-bottom:1rem;">$1</h1>')
          .replace(/## (.*?)\n/g, '<h2 style="color:var(--accent-secondary); margin-top:1.5rem;">$1</h2>')
          .replace(/### (.*?)\n/g, '<h3 style="color:#fff; margin-top:1rem;">$1</h3>')
          .replace(/\n\n/g, '<br/><br/>');
        trendContent.innerHTML = html;
      }
    } catch (err) {
      trendContent.innerHTML = `<p style="color:#ef4444;">トレンド取得エラー: ${err.message}</p>`;
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
