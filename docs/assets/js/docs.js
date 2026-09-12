const sidebar = document.querySelector('#sidebar');
const menuToggle = document.querySelector('#menu-toggle');
const search = document.querySelector('#nav-search');

menuToggle?.addEventListener('click', () => {
  const open = sidebar.classList.toggle('is-open');
  menuToggle.setAttribute('aria-expanded', String(open));
});

search?.addEventListener('input', () => {
  const query = search.value.trim().toLowerCase();

  document.querySelectorAll('.nav-section').forEach((section) => {
    let visible = false;

    section.querySelectorAll('li').forEach((item) => {
      const matches = !query || item.textContent.toLowerCase().includes(query);
      item.hidden = !matches;
      visible ||= matches;
    });

    section.hidden = !visible;
  });
});
