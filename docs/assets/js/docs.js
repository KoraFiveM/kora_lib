const sidebar = document.querySelector('#sidebar');
const menuToggle = document.querySelector('#menu-toggle');
const search = document.querySelector('#nav-search');
const content = document.querySelector('#content');
const methodsSidebar = document.querySelector('#methods-sidebar');
const methodsNav = document.querySelector('#methods-nav');

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

const methodHeadings = [...(content?.querySelectorAll('h2, h3') ?? [])].filter((heading) =>
  heading.textContent.trim().startsWith('Kora.')
);

if (methodsSidebar && methodsNav && methodHeadings.length > 0) {
  const methodList = document.createElement('ol');
  const links = methodHeadings.map((heading, index) => {
    if (!heading.id) heading.id = `method-${index + 1}`;

    const item = document.createElement('li');
    const link = document.createElement('a');
    link.href = `#${heading.id}`;
    link.textContent = heading.textContent.trim();
    item.append(link);
    methodList.append(item);
    return link;
  });

  methodsNav.append(methodList);
  methodsSidebar.hidden = false;

  let scheduled = false;
  const updateActiveMethod = () => {
    const activeIndex = methodHeadings.reduce(
      (current, heading, index) => heading.getBoundingClientRect().top <= 120 ? index : current,
      0
    );

    links.forEach((link, index) => {
      const active = index === activeIndex;
      link.classList.toggle('is-active', active);
      if (active) link.setAttribute('aria-current', 'location');
      else link.removeAttribute('aria-current');
    });
    scheduled = false;
  };

  window.addEventListener('scroll', () => {
    if (scheduled) return;
    scheduled = true;
    window.requestAnimationFrame(updateActiveMethod);
  }, { passive: true });
  updateActiveMethod();
}
