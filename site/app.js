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
  const modalTxtLink = document.getElementById('modalTxtLink');
  const modalOkfLink = document.getElementById('modalOkfLink');

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

  let currentOffset = 0;
  let currentLimit = 12;
  let currentTotalHits = 0;
  let currentLoadedCount = 0;

  const pageSizeSelect = document.getElementById('pageSizeSelect');
  const loadMoreContainer = document.getElementById('loadMoreContainer');
  const loadMoreBtn = document.getElementById('loadMoreBtn');
  const allLoadedMsg = document.getElementById('allLoadedMsg');

  if (pageSizeSelect) {
    pageSizeSelect.addEventListener('change', () => {
      currentLimit = parseInt(pageSizeSelect.value, 10) || 12;
      performSearch(searchInput.value, true, 0, false);
    });
  }

  if (loadMoreBtn) {
    loadMoreBtn.addEventListener('click', () => {
      const nextOffset = currentOffset + currentLimit;
      performSearch(searchInput.value, false, nextOffset, true);
    });
  }

  // Perform RAG Search & Update URL
  async function performSearch(query, updateUrl = true, offset = 0, append = false) {
    const cleanQuery = (query === null || query === undefined) ? '' : String(query).trim();
    currentOffset = offset;

    if (updateUrl) {
      const params = new URLSearchParams();
      if (cleanQuery) params.set('q', cleanQuery);
      if (activeTag) params.set('tag', activeTag);
      if (currentLimit !== 12) params.set('limit', String(currentLimit));
      const newUrl = window.location.pathname + (params.toString() ? '?' + params.toString() : '');
      history.pushState({ q: cleanQuery, tag: activeTag, limit: currentLimit }, '', newUrl);
    }

    const startTime = performance.now();
    if (!append) {
      resultsGrid.innerHTML = '<p style="color: var(--text-muted);">検索中...</p>';
      if (loadMoreContainer) loadMoreContainer.style.display = 'none';
      currentLoadedCount = 0;
    } else if (loadMoreBtn) {
      loadMoreBtn.disabled = true;
      loadMoreBtn.innerHTML = '<span>⏳ 読み込み中...</span>';
    }
    
    try {
      let url = `/api/search?q=${encodeURIComponent(cleanQuery)}&top_k=${currentLimit}&offset=${offset}`;
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
        currentTotalHits = Number(data.total_hits !== undefined ? data.total_hits : data.results.length);
        renderResults(data.results, append, data.has_more);
      } else {
        if (!append) {
          resultsGrid.innerHTML = '<p class="loading-text">該当する論文は見つかりませんでした。</p>';
          resultsCount.textContent = '検索結果 (0件)';
          if (loadMoreContainer) loadMoreContainer.style.display = 'none';
        }
      }
    } catch (err) {
      if (!append) {
        resultsGrid.innerHTML = `<p style="color: #ef4444;">検索エラーが発生しました: ${escapeHtml(err.message)}</p>`;
      }
    } finally {
      if (loadMoreBtn) {
        loadMoreBtn.disabled = false;
        loadMoreBtn.innerHTML = `<span>⬇️ さらに読み込む (次の${currentLimit}件)</span>`;
      }
    }
  }

  // Render Paper Cards
  function renderResults(results, append = false, hasMore = false) {
    if (!append) {
      currentLoadedCount = results.length;
    } else {
      currentLoadedCount += results.length;
    }

    if (currentLoadedCount === 0) {
      resultsCount.textContent = '検索結果 (0件)';
      resultsGrid.innerHTML = '<p class="loading-text">該当する論文は見つかりませんでした。</p>';
      if (loadMoreContainer) loadMoreContainer.style.display = 'none';
      return;
    }

    resultsCount.textContent = `検索結果: 全 ${currentTotalHits.toLocaleString()} 件中 1〜${currentLoadedCount.toLocaleString()} 件を表示`;

    const cardsHtml = results.map(paper => {
      const authors = (paper['authors'] || []).slice(0, 3).join(', ');
      const authorsBadge = authors ? `<div class="card-authors">👥 著者: ${escapeHtml(authors)}</div>` : '';
      const highlightHtml = paper['highlight'] ? `<div class="card-snippet">${paper['highlight']}</div>` : `<p class="card-desc">${escapeHtml(paper.description || '要約情報なし')}</p>`;
      const okfPath = paper.path ? ('/' + encodeURI(paper.path)) : '#';
      const rawTxtPath = paper.path ? ('/' + encodeURI(paper.path.replace('outputs/okf_papers/', 'raw_data/').replace('.md', '.txt'))) : '#';
      const previewUrl = `/preview/${encodeURIComponent(paper.id)}`;

      return `
      <div class="glass-panel paper-card">
        <div style="cursor: pointer;" onclick="openPaperModal('${escapeHtml(paper.id)}')">
          <div class="card-top">
            <span class="arxiv-id-tag">arXiv: ${escapeHtml(paper.id)}</span>
            <span class="score-badge">Score: ${escapeHtml(String(paper['score']))}</span>
          </div>
          <h3 class="card-title">${escapeHtml(paper.title)}</h3>
          ${authorsBadge}
          ${highlightHtml}
        </div>
        <div class="card-footer">
          <div class="card-tags">
            ${(paper.tags || []).slice(0, 2).map(t => `<span class="mini-tag">${escapeHtml(t)}</span>`).join('')}
          </div>
          <div class="card-actions-row">
            <a href="${rawTxtPath}" target="_blank" rel="noopener" class="card-action-link" title="PDF全文テキスト抽出ファイル (.txt)" onclick="event.stopPropagation()">📜 生テキスト</a>
            <a href="${okfPath}" target="_blank" rel="noopener" class="card-action-link" title="生の OKF Markdown をプレーンテキストで表示 (.md)" onclick="event.stopPropagation()">📝 .md</a>
            <a href="${previewUrl}" target="_blank" rel="noopener" class="card-action-link" title="スタンドアロン HTML プレビュー" onclick="event.stopPropagation()">👁️ プレビュー ↗</a>
            <button class="card-action-btn" onclick="openPaperModal('${escapeHtml(paper.id)}')">詳細 &rarr;</button>
          </div>
        </div>
      </div>
      `;
    }).join('');

    if (append) {
      resultsGrid.insertAdjacentHTML('beforeend', cardsHtml);
    } else {
      resultsGrid.innerHTML = cardsHtml;
    }

    // Manage Load More & All Loaded visibility
    if (loadMoreContainer) {
      loadMoreContainer.style.display = 'block';
      if (hasMore) {
        if (loadMoreBtn) loadMoreBtn.style.display = 'inline-flex';
        if (allLoadedMsg) allLoadedMsg.style.display = 'none';
      } else {
        if (loadMoreBtn) loadMoreBtn.style.display = 'none';
        if (allLoadedMsg) {
          allLoadedMsg.style.display = 'block';
          allLoadedMsg.textContent = `🎉 すべての検索結果（全 ${currentTotalHits.toLocaleString()} 件）を表示しました`;
        }
      }
    }
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
      if (data.status === 'success') {
        const rawContent = data.content || (data.paper ? `# ${data.paper.title}\n\n## 概要\n${data.paper.description || data.paper.summary || ''}` : '');
        const paperMeta = data.paper || {};
        const paperPath = data.path || paperMeta.path || '';

        if (modalOkfLink && paperPath) modalOkfLink.href = '/' + encodeURI(paperPath);
        if (modalTxtLink && paperPath) {
          modalTxtLink.href = '/' + encodeURI(paperPath.replace('outputs/okf_papers/', 'raw_data/').replace('.md', '.txt'));
        }

        const titleEn = paperMeta.title || rawContent.match(/title:\s*"(.*?)"/)?.[1] || arxivId;
        const titleJa = paperMeta.title_ja || rawContent.match(/title_ja:\s*"(.*?)"/)?.[1] || '';

        modalPaperTitle.textContent = titleEn;
        modalPaperTitleJa.textContent = titleJa;
        
        if (rawContent && window.MarkdownCompiler) {
          const compiled = window.MarkdownCompiler.compile(rawContent);
          modalPaperBody.innerHTML = compiled.html;
        } else if (rawContent) {
          modalPaperBody.innerHTML = `<pre style="white-space:pre-wrap;">${escapeHtml(rawContent)}</pre>`;
        } else {
          modalPaperBody.innerHTML = `<p>論文データが見つかりませんでした。</p>`;
        }

        // Fetch & Render Related Papers Proximity Network
        fetchRelatedPapersTopology(arxivId, modalPaperBody);

        if (window.MarkdownCompiler && window.MarkdownCompiler.renderMermaid) {
          window.MarkdownCompiler.renderMermaid(modalPaperBody);
        }
      } else {
        modalPaperBody.innerHTML = `<p style="color:#ef4444;">エラー: ${escapeHtml(data.message || 'データが見つかりませんでした')}</p>`;
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
    } else if (selected === 'verify_code_security') {
      mcpArgsInput.value = JSON.stringify({
        code_snippet: "def login(user, pwd):\n    query = f\"SELECT * FROM users WHERE u='{user}' AND p='{pwd}'\"\n    cursor.execute(query)",
        language: "python"
      }, null, 2);
    } else if (selected === 'get_cwe_mitigation_recipe') {
      mcpArgsInput.value = JSON.stringify({ cwe_id: "CWE-89" }, null, 2);
    } else if (selected === 'get_related_papers_graph') {
      mcpArgsInput.value = JSON.stringify({ arxiv_id: "2502.16730" }, null, 2);
    } else if (selected === 'get_paper_summary') {
      mcpArgsInput.value = JSON.stringify({ arxiv_id: "2502.16730" }, null, 2);
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
