
{
  function clearBrowserElements() {
    for (const element of document.getElementById('browser').children) {
      element.style.display = 'none';
    }
  }

  function getMotion() {
    return gZenUIManager.motion;
  }

  async function animate(...args) {
    return getMotion().animate(...args);
  }

  function initializeZenWelcome() {
    const XUL = `
      <html:div id="zen-welcome">
        <html:div id="zen-welcome-start">
          <html:h1 class="zen-branding-title" id="zen-welcome-title"></html:h1>
          <button class="footer-button primary" id="zen-welcome-start-button">
          </button>
        </html:div>
      </html:div>
    `;
    const fragment = window.MozXULElement.parseXULToFragment(XUL);
    document.getElementById('browser').appendChild(fragment);
    window.MozXULElement.insertFTLIfNeeded("browser/zen-welcome.ftl");
  }

  async function animateInitialStage() {
    const [title1, title2] = await document.l10n.formatValues([{id:'zen-welcome-title-line1'}, {id:'zen-welcome-title-line2'}]);
    const titleElement = document.getElementById('zen-welcome-title');
    titleElement.innerHTML = `<html:span>${title1}</html:span><html:span>${title2}</html:span>`;
    await animate("#zen-welcome-title span", { opacity: [0, 1], y: [100, 0] }, {
      delay: getMotion().stagger(0.6),
      type: 'spring',
      ease: 'ease-out',
      bounce: 0,
    });
    await animate("#zen-welcome-start-button", { opacity: [0, 1], y: [100, 0] }, {
      delay: 0.5,
      type: 'spring',
      ease: 'ease-in-out',
      bounce: 0.4,
    });
  }

  function startZenWelcome() {
    clearBrowserElements();
    initializeZenWelcome();
    animateInitialStage();
  }

  startZenWelcome();
}
