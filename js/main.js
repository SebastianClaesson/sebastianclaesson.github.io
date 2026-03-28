// Theme: apply saved preference before paint
(function() {
  const saved = localStorage.getItem('theme');
  if (saved) {
    document.documentElement.setAttribute('data-theme', saved);
  }
})();

// Mobile nav toggle
document.addEventListener('DOMContentLoaded', () => {

  // Theme toggle
  const themeBtn = document.querySelector('.theme-toggle');
  if (themeBtn) {
    themeBtn.addEventListener('click', () => {
      const current = document.documentElement.getAttribute('data-theme');
      const isDark = current === 'dark' ||
        (!current && window.matchMedia('(prefers-color-scheme: dark)').matches);
      const next = isDark ? 'light' : 'dark';
      document.documentElement.setAttribute('data-theme', next);
      localStorage.setItem('theme', next);
    });
  }
  const toggle = document.querySelector('.nav-toggle');
  const menu = document.querySelector('.nav-menu');

  if (toggle && menu) {
    toggle.addEventListener('click', () => {
      menu.classList.toggle('open');
    });
  }

  // Back to top button
  const btn = document.querySelector('.back-to-top');
  if (btn) {
    window.addEventListener('scroll', () => {
      btn.classList.toggle('visible', window.scrollY > 400);
    });
    btn.addEventListener('click', () => {
      window.scrollTo({ top: 0, behavior: 'smooth' });
    });
  }

  // Highlight.js init
  if (typeof hljs !== 'undefined') {
    hljs.highlightAll();
  }

  // Draft posts: show when ?drafts=true is in the URL
  const params = new URLSearchParams(window.location.search);
  const showDrafts = params.get('drafts') === 'true';
  if (showDrafts) {
    document.querySelectorAll('.draft-post').forEach(el => {
      el.style.display = '';
    });
  }

  // Search & category filter
  const searchInput = document.getElementById('search-input');
  const catButtons = document.querySelectorAll('.cat-btn');
  const noResults = document.getElementById('no-results');
  let activeCategory = 'all';

  function filterPosts() {
    const query = searchInput ? searchInput.value.toLowerCase().trim() : '';
    const cards = document.querySelectorAll('.post-card');
    let visible = 0;

    cards.forEach(card => {
      const isDraft = card.classList.contains('draft-post');
      if (isDraft && !showDrafts) return; // skip hidden drafts

      const title = (card.querySelector('h2') || {}).textContent || '';
      const desc = (card.querySelector('p') || {}).textContent || '';
      const tags = Array.from(card.querySelectorAll('.post-card-tags span'))
        .map(t => t.textContent).join(' ');
      const categories = (card.dataset.categories || '').split(',');

      const matchesSearch = !query ||
        title.toLowerCase().includes(query) ||
        desc.toLowerCase().includes(query) ||
        tags.toLowerCase().includes(query);

      const matchesCategory = activeCategory === 'all' ||
        categories.some(c => c.trim() === activeCategory);

      if (matchesSearch && matchesCategory) {
        card.style.display = '';
        visible++;
      } else {
        card.style.display = 'none';
      }
    });

    if (noResults) {
      noResults.style.display = visible === 0 ? '' : 'none';
    }
  }

  if (searchInput) {
    searchInput.addEventListener('input', filterPosts);
  }

  catButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      catButtons.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      activeCategory = btn.dataset.category;
      filterPosts();
    });
  });
});
