document.addEventListener('DOMContentLoaded', () => {
  let activeTag = '';
  let activePeriod = 'monthly';
  let currentSearchResults = [];

  // DOM Elements
  const searchInput = document.getElementById('searchInput');
  const searchBtn = document.getElementById('searchBtn');
  const globalSearchInput = document.getElementById('globalSearchInput');
  const clearFiltersBtn = document.getElementById('clearFiltersBtn');
  const resultsGrid = document.getElementById('resultsGrid');
  const resultsCount = document.getElementById('resultsCount');
  const searchTime = document.getElementById('searchTime');
  const totalPapersCount = document.getElementById('totalPapersCount');
  const sidebarPapersCount = document.getElementById('sidebarPapersCount');
  const mainPageTitle = document.getElementById('mainPageTitle');
  const mainPageSubtitle = document.getElementById('mainPageSubtitle');
  
  const consoleSidebar = document.getElementById('consoleSidebar');
  const sidebarToggleBtn = document.getElementById('sidebarToggleBtn');
  const systemInfoBanner = document.getElementById('systemInfoBanner');
  const closeBannerBtn = document.getElementById('closeBannerBtn');

  const refreshDataBtn = document.getElementById('refreshDataBtn');
  const exportDataBtn = document.getElementById('exportDataBtn');
  const guideHelpBtn = document.getElementById('guideHelpBtn');
  const helpModalBtn = document.getElementById('helpModalBtn');
  const notifBtn = document.getElementById('notifBtn');
  
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

  // ========================================================================
  // 1. Sidebar Navigation, Accordions, & Collapsible Toggle
  // ========================================================================
  if (sidebarToggleBtn && consoleSidebar) {
    sidebarToggleBtn.addEventListener('click', () => {
      consoleSidebar.classList.toggle('collapsed');
      const isCollapsed = consoleSidebar.classList.contains('collapsed');
      sidebarToggleBtn.textContent = isCollapsed ? '▶' : '◀';
      sidebarToggleBtn.title = isCollapsed ? 'サイドバー展開' : 'サイドバー折りたたみ';
    });
  }

  // Accordion Expand/Collapse
  document.querySelectorAll('.nav-group-header').forEach(header => {
    header.addEventListener('click', (e) => {
      e.preventDefault();
      const parentGroup = header.closest('.nav-group');
      if (parentGroup) {
        parentGroup.classList.toggle('collapsed');
      }
    });
  });

  // Tab switching via Nav Items
  const navTabBtns = document.querySelectorAll('.nav-tab-btn');
  navTabBtns.forEach(btn => {
    btn.addEventListener('click', (e) => {
      const tabId = btn.getAttribute('data-tab');
      if (tabId) {
        e.preventDefault();
        switchToTab(tabId);
        const hash = btn.getAttribute('href');
        if (hash && hash.startsWith('#/')) {
          history.pushState(null, '', hash);
        }
      }
    });
  });

  function switchToTab(tabId) {
    // Update sidebar active indicators
    document.querySelectorAll('.nav-item').forEach(b => b.classList.remove('active'));
    const targetNav = document.querySelector(`.nav-tab-btn[data-tab="${tabId}"]`);
    if (targetNav) targetNav.classList.add('active');

    // Update main container tabs
    document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
    const targetTab = document.getElementById(tabId);
    if (targetTab) targetTab.classList.add('active');

    // Update Header Titles
    if (tabId === 'searchTab') {
      if (mainPageTitle) mainPageTitle.textContent = '🔍 セマンティック RAG 論文検索 & 脅威インテリジェンス';
      if (mainPageSubtitle) mainPageSubtitle.textContent = 'Google OKF v0.2 準拠の 14,169 件のセキュリティ学術論文および ATT&CK 推論メタデータを横断探索';
    } else if (tabId === 'trendsTab') {
      if (mainPageTitle) mainPageTitle.textContent = '📊 階層別エグゼクティブサマリー & トレンド分析';
      if (mainPageSubtitle) mainPageSubtitle.textContent = '月次・四半期・通期セキュリティ研究動向と ATT&CK 手法・脅威動向のクラスタリング';
      fetchTrends(activePeriod);
    } else if (tabId === 'mcpTab') {
      if (mainPageTitle) mainPageTitle.textContent = '🔌 Model Context Protocol (MCP) JSON-RPC サンドボックス';
      if (mainPageSubtitle) mainPageSubtitle.textContent = 'AI エージェント・外部システム向け標準ツール呼び出しインターフェースの即時テスト環境';
    }
  }

  // Hash-based Routing
  function handleHashRoute() {
    const hash = window.location.hash;
    if (hash === '#/trends') {
      switchToTab('trendsTab');
    } else if (hash === '#/mcp') {
      switchToTab('mcpTab');
    } else {
      switchToTab('searchTab');
    }
  }

  window.addEventListener('hashchange', handleHashRoute);
  if (window.location.hash) {
    handleHashRoute();
  }

  // ========================================================================
  // 2. Global Search & Keyboard Shortcuts (Ctrl+K, /)
  // ========================================================================
  window.addEventListener('keydown', (e) => {
    // Ctrl+K or Cmd+K
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      if (globalSearchInput) {
        globalSearchInput.focus();
        globalSearchInput.select();
      } else if (searchInput) {
        searchInput.focus();
        searchInput.select();
      }
    }
    // Slash shortcut outside input
    if (e.key === '/' && document.activeElement.tagName !== 'INPUT' && document.activeElement.tagName !== 'TEXTAREA') {
      e.preventDefault();
      if (globalSearchInput) {
        globalSearchInput.focus();
      }
    }
  });

  if (globalSearchInput) {
    globalSearchInput.addEventListener('keypress', (e) => {
      if (e.key === 'Enter') {
        const query = globalSearchInput.value.trim();
        if (searchInput) searchInput.value = query;
        switchToTab('searchTab');
        performSearch(query, true);
      }
    });
  }

  // ========================================================================
  // 3. Banner & Utility Buttons
  // ========================================================================
  if (closeBannerBtn && systemInfoBanner) {
    closeBannerBtn.addEventListener('click', () => {
      systemInfoBanner.style.display = 'none';
    });
  }

  if (clearFiltersBtn) {
    clearFiltersBtn.addEventListener('click', () => {
      activeTag = '';
      if (searchInput) searchInput.value = '';
      if (globalSearchInput) globalSearchInput.value = '';
      document.querySelectorAll('.filter-pill').forEach(c => {
        if (c.getAttribute('data-tag') === '') c.classList.add('active');
        else c.classList.remove('active');
      });
      performSearch('', true);
    });
  }

  if (refreshDataBtn) {
    refreshDataBtn.addEventListener('click', () => {
      fetchStats();
      performSearch(searchInput ? searchInput.value : '', false);
    });
  }

  if (exportDataBtn) {
    exportDataBtn.addEventListener('click', () => {
      if (!currentSearchResults || currentSearchResults.length === 0) {
        alert('エクスポート対象の検索結果がありません。');
        return;
      }
      const dataStr = 'data:text/json;charset=utf-8,' + encodeURIComponent(JSON.stringify(currentSearchResults, null, 2));
      const downloadAnchor = document.createElement('a');
      downloadAnchor.setAttribute('href', dataStr);
      downloadAnchor.setAttribute('download', `arxiv_security_papers_${new Date().toISOString().slice(0, 10)}.json`);
      document.body.appendChild(downloadAnchor);
      downloadAnchor.click();
      downloadAnchor.remove();
    });
  }

  function showHelpModal() {
    alert("【arXiv Security Intelligence - 操作ガイド】\n\n1. グローバル検索 (Ctrl+K):\n   画面上部から論文ID、攻撃手法名、脆弱性番号を横断検索可能。\n\n2. セマンティック RAG 検索:\n   ペンテスト自動化、LLM 脆弱性などの日本語自然言語クエリから類似論文を即時抽出。\n\n3. CTI ナレッジグラフ:\n   左サイドバーから ATT&CK マトリクスや推論ルール (EIROM) グラフへ直接遷移可能。\n\n4. MCP JSON-RPC サンドボックス:\n   外部 AI エージェント用の各種 MCP ツールを Web 上で直接検証。");
  }

  if (guideHelpBtn) guideHelpBtn.addEventListener('click', showHelpModal);
  if (helpModalBtn) helpModalBtn.addEventListener('click', showHelpModal);
  if (notifBtn) {
    notifBtn.addEventListener('click', () => {
      alert("🔔【通知センター】\n・2026-09-05 06:00 定期バッチ完了 (新着 24 件)\n・EIROM 推論エンジン: 84.2% HIGH 確信度維持\n・未研究リサーチギャップ: 12 件検出中");
    });
  }

  // ========================================================================
  // 4. Search Initialization & Execution
  // ========================================================================
  const urlParams = new URLSearchParams(window.location.search);
  const initialQuery = urlParams.get('q') || urlParams.get('query');
  const initialTag = urlParams.get('tag') || urlParams.get('category');

  if (initialTag) {
    activeTag = initialTag;
    document.querySelectorAll('.filter-pill').forEach(c => {
      if (c.getAttribute('data-tag') === initialTag) c.classList.add('active');
      else c.classList.remove('active');
    });
  }

  fetchStats();
  const queryToRun = initialQuery !== null ? initialQuery : "ペンテスト";
  if (searchInput) searchInput.value = queryToRun;
  if (globalSearchInput) globalSearchInput.value = queryToRun;
  performSearch(queryToRun, false);

  // Filter Pills
  document.querySelectorAll('.filter-pill').forEach(chip => {
    chip.addEventListener('click', () => {
      document.querySelectorAll('.filter-pill').forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      activeTag = chip.getAttribute('data-tag');
      performSearch(searchInput.value, true);
    });
  });

  // Search Events
  if (searchBtn && searchInput) {
    searchBtn.addEventListener('click', () => performSearch(searchInput.value, true));
    searchInput.addEventListener('keypress', (e) => {
      if (e.key === 'Enter') performSearch(searchInput.value, true);
    });
  }

  // Browser Navigation History (Popstate)
  window.addEventListener('popstate', () => {
    const params = new URLSearchParams(window.location.search);
    const q = params.get('q') || '';
    const tag = params.get('tag') || '';
    activeTag = tag;
    document.querySelectorAll('.filter-pill').forEach(c => {
      if (c.getAttribute('data-tag') === tag) c.classList.add('active');
      else c.classList.remove('active');
    });
    if (searchInput) searchInput.value = q;
    if (globalSearchInput) globalSearchInput.value = q;
    performSearch(q, false);
  });

  // Fetch System Stats
  async function fetchStats() {
    try {
      const res = await fetch('/api/stats');
      const data = await res.json();
      if (data.total_papers) {
        const formatted = Number(data.total_papers).toLocaleString();
        if (totalPapersCount) totalPapersCount.textContent = formatted;
        if (sidebarPapersCount) sidebarPapersCount.textContent = formatted;
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
      const newUrl = window.location.pathname + (params.toString() ? '?' + params.toString() : '') + (window.location.hash || '');
      history.pushState({ q: cleanQuery, tag: activeTag, limit: currentLimit }, '', newUrl);
    }

    const startTime = performance.now();
    if (!append) {
      resultsGrid.innerHTML = '<p style="color: var(--console-fg-muted); padding: 16px;">検索中...</p>';
      if (loadMoreContainer) loadMoreContainer.style.display = 'none';
      currentLoadedCount = 0;
      currentSearchResults = [];
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
        currentTotalHits = Number(data['total_hits'] !== undefined ? data['total_hits'] : data.results.length);
        if (append) {
          currentSearchResults = currentSearchResults.concat(data.results);
        } else {
          currentSearchResults = data.results;
        }
        renderResults(data.results, append, data['has_more']);
      } else {
        if (!append) {
          resultsGrid.innerHTML = '<p class="loading-text" style="padding: 16px;">該当する論文は見つかりませんでした。</p>';
          resultsCount.textContent = '検索結果 (0件)';
          if (loadMoreContainer) loadMoreContainer.style.display = 'none';
        }
      }
    } catch (err) {
      if (!append) {
        resultsGrid.innerHTML = `<p style="color: #ef4444; padding: 16px;">検索エラーが発生しました: ${escapeHtml(err.message)}</p>`;
      }
    } finally {
      if (loadMoreBtn) {
        loadMoreBtn.disabled = false;
        loadMoreBtn.innerHTML = `<span>⬇️ さらに読み込む (次の${currentLimit}件)</span>`;
      }
    }
  }

  // Render Paper Cards (Enterprise Resource Presentation)
  function renderResults(results, append = false, hasMore = false) {
    if (!append) {
      currentLoadedCount = results.length;
    } else {
      currentLoadedCount += results.length;
    }

    if (currentLoadedCount === 0) {
      resultsCount.textContent = '検索結果 (0件)';
      resultsGrid.innerHTML = '<p class="loading-text" style="padding: 16px;">該当する論文は見つかりませんでした。</p>';
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
      <div class="paper-card">
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
            <button class="action-dots-btn" title="詳細アクション" onclick="event.stopPropagation(); openPaperModal('${escapeHtml(paper.id)}')">⋮</button>
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

  // ========================================================================
  // 5. Fullscreen Modal Viewer
  // ========================================================================
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
        if (window.MarkdownCompiler && window.MarkdownCompiler.renderMermaid) {
          window.MarkdownCompiler.renderMermaid(section);
        }
      }
    } catch (e) {
      console.warn('Could not load related papers:', e);
    }
  }

  function closeFullscreenModal() {
    paperModal.classList.add('hidden');
    document.body.style.overflow = '';
  }

  if (closeModalBtn) closeModalBtn.addEventListener('click', closeFullscreenModal);
  window.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !paperModal.classList.contains('hidden')) {
      closeFullscreenModal();
    }
  });

  // ========================================================================
  // 6. Trends Tab Logic
  // ========================================================================
  document.querySelectorAll('.period-btn').forEach(btn => {
    btn.addEventListener('click', () => {
      document.querySelectorAll('.period-btn').forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      activePeriod = btn.getAttribute('data-period');
      fetchTrends(activePeriod);
    });
  });

  async function fetchTrends(period) {
    if (!trendContent) return;
    trendContent.innerHTML = '<p class="loading-text">トレンドデータを取得中...</p>';
    try {
      const res = await fetch(`/api/trends?period=${encodeURIComponent(period)}`);
      const data = await res.json();
      if (data.status === 'success' && data.content) {
        const compiled = window.MarkdownCompiler.compile(data.content);
        trendContent.innerHTML = compiled.html;
        if (window.MarkdownCompiler && window.MarkdownCompiler.renderMermaid) {
          window.MarkdownCompiler.renderMermaid(trendContent);
        }
      }
    } catch (err) {
      trendContent.innerHTML = `<p style="color:#ef4444;">トレンド取得エラー: ${escapeHtml(err.message)}</p>`;
    }
  }

  // ========================================================================
  // 7. MCP Sandbox Logic
  // ========================================================================
  if (mcpToolSelect && mcpArgsInput) {
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
  }

  if (runMcpBtn && mcpOutput && mcpToolSelect && mcpArgsInput) {
    runMcpBtn.addEventListener('click', async () => {
      mcpOutput.textContent = '⚡ MCP JSON-RPC 呼び出し中...';
      let args;
      try {
        args = JSON.parse(mcpArgsInput.value);
      } catch (err) {
        mcpOutput.textContent = `引数 (JSON) パースエラー: ${err.message}\n正しい JSON 形式（キーをダブルクォートで囲む等）で入力してください。`;
        return;
      }

      try {
        const name = mcpToolSelect.value;
        const res = await fetch('/api/mcp', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ name, arguments: args })
        });
        const data = await res.json();
        mcpOutput.textContent = JSON.stringify(data, null, 2);
      } catch (err) {
        mcpOutput.textContent = `API 呼び出しエラー: ${err.message}`;
      }
    });
  }

  function escapeHtml(str) {
    if (!str) return '';
    return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }
});
