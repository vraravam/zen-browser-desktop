
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
    document.documentElement.setAttribute('zen-welcome-stage', 'true');
    const XUL = `
      <html:div id="zen-welcome">
        <html:div id="zen-welcome-start">
          <html:h1 class="zen-branding-title" id="zen-welcome-title"></html:h1>
          <button class="footer-button primary" id="zen-welcome-start-button">
          </button>
        </html:div>
        <hbox id="zen-welcome-pages">
          <vbox id="zen-welcome-page-sidebar">
            <vbox id="zen-welcome-page-sidebar-content">
            </vbox>
            <vbox id="zen-welcome-page-sidebar-buttons">
            </vbox>
          </vbox>
          <html:div id="zen-welcome-page-content">
          </html:div>
        </hbox>
      </html:div>
    `;
    const fragment = window.MozXULElement.parseXULToFragment(XUL);
    document.getElementById('browser').appendChild(fragment);
    window.MozXULElement.insertFTLIfNeeded('browser/zen-welcome.ftl');
  }

  class ZenWelcomePages {
    constructor(pages) {
      this._currentPage = -1;
      this._pages = pages;
      this.init();
      this.next();
    }

    init() {
      document.getElementById('zen-welcome-pages').style.display = 'flex';
      document.getElementById('zen-welcome-start').remove();
      window.maximize();
      animate('#zen-welcome-pages', { opacity: [0, 1] });
    }

    async fadeInTitles(page) {
      const [title1, description1, description2] = await document.l10n.formatValues(page.text);
      const titleElement = document.getElementById('zen-welcome-page-sidebar-content');
      titleElement.innerHTML = `<html:h1>${title1}</html:h1><html:p>${description1}</html:p>`
        + (description2 ? `<html:p>${description2}</html:p>` : '');
      await animate(
        '#zen-welcome-page-sidebar-content > *',
        { opacity: [0, 1], x: [50, 0], filter: ['blur(2px)', 'blur(0px)'] },
        {
          delay: getMotion().stagger(0.05, { startDelay: 0.3 }),
          type: 'spring',
          bounce: 0.2,
        }
      );
    }

    async fadeInButtons(page) {
      const buttons = document.getElementById('zen-welcome-page-sidebar-buttons');
      let i = 0;
      for (const button of page.buttons) {
        const buttonElement = document.createXULElement('button');
        document.l10n.setAttributes(buttonElement, button.l10n);
        if (i++ === 0) {
          buttonElement.classList.add('primary');
        }
        buttonElement.classList.add('footer-button');
        buttonElement.addEventListener('click', async () => {
          const shouldSkip = await button.onclick();
          if (shouldSkip) {
            this.next();
          }
        });
        buttons.appendChild(buttonElement);
      }
      await animate(
        '#zen-welcome-page-sidebar-buttons button',
        { opacity: [0, 1], x: [50, 0], filter: ['blur(2px)', 'blur(0px)'] },
        {
          delay: getMotion().stagger(0.1),
          type: 'spring',
          bounce: 0.2,
        }
      );
    }

    async fadeInContent(page) {
      const contentElement = document.getElementById('zen-welcome-page-content');
      contentElement.innerHTML = page.content;
      await animate(
        '#zen-welcome-page-content > *',
        { opacity: [0, 1], scale: [0.9, 1], filter: ['blur(2px)', 'blur(0px)'] },
        {
          delay: getMotion().stagger(0.05, { startDelay: 0.3 }),
          type: 'spring',
          bounce: 0.2,
        }
      );
    }

    async fadeOutButtons() {
      await animate(
        '#zen-welcome-page-sidebar-buttons button',
        { opacity: [1, 0], x: [0, -60], filter: ['blur(0px)', 'blur(2px)'] },
        {
          type: 'spring',
          stiffness: 300,
          damping: 20,
          mass: 1.4,
        }
      );
      document.getElementById('zen-welcome-page-sidebar-buttons').innerHTML = '';
      document.getElementById('zen-welcome-page-sidebar-content').innerHTML = '';
    }

    async fadeOutTitles() {
      await animate(
        '#zen-welcome-page-content-title h1, #zen-welcome-page-content-title p',
        { opacity: [1, 0], x: [0, -60], filter: ['blur(0px)', 'blur(2px)'] },
        {
          type: 'spring',
          stiffness: 300,
          damping: 20,
          mass: 1.4,
        }
      );
    }

    async next() {
      if (this._currentPage !== -1) {
        const previousPage = this._pages[this._currentPage];
        await this.fadeOutTitles();
        await this.fadeOutButtons();
        previousPage.fadeOut();
      }
      this._currentPage++;
      const currentPage = this._pages[this._currentPage];
      if (!currentPage) {
        this.finish();
        return;
      }
      await this.fadeInTitles(currentPage);
      await this.fadeInButtons(currentPage);
      await this.fadeInContent(currentPage);
      currentPage.fadeIn();
    }

    finish() {
      document.documentElement.removeAttribute('zen-welcome-stage');
    }
  }

  function getWelcomePages() {
    return [
      {
        text: [
          {
            id: 'zen-welcome-import-title',
          },
          {
            id: 'zen-welcome-import-description-1',
          },
          {
            id: 'zen-welcome-import-description-2',
          }
        ],
        buttons: [
          {
            l10n: 'zen-welcome-import-button',
            onclick: async () => {
              MigrationUtils.showMigrationWizard(window, {
                zenBlocking: true,
              });
              return false;
            },
          },
          {
            l10n: 'zen-welcome-skip-button',
            onclick: async () => {
              return true;
            },
          },
        ],
        content: `
          <checkbox
            class="clearingItemCheckbox"
            data-l10n-id="item-history-form-data-downloads"
            id="zen-welcome-set-default-browser"
          />
        `,
        fadeIn() {},
        fadeOut() {},
      },
    ];
  }

  async function animateInitialStage() {
    const [title1, title2] = await document.l10n.formatValues([
      { id: 'zen-welcome-title-line1' },
      { id: 'zen-welcome-title-line2' },
    ]);
    const titleElement = document.getElementById('zen-welcome-title');
    titleElement.innerHTML = `<html:span>${title1}</html:span><html:span>${title2}</html:span>`;
    await animate(
      '#zen-welcome-title span',
      { opacity: [0, 1], y: [30, 0], filter: ['blur(2px)', 'blur(0px)'] },
      {
        delay: getMotion().stagger(0.6, { startDelay: 0.2 }),
        type: 'spring',
        stiffness: 300,
        damping: 20,
        mass: 1.7,
      }
    );
    const button = document.getElementById('zen-welcome-start-button');
    await animate(
      button,
      { opacity: [0, 1], y: [30, 0], filter: ['blur(2px)', 'blur(0px)'] },
      {
        delay: 0.6,
        type: 'spring',
        stiffness: 300,
        damping: 20,
        mass: 1.7,
      }
    );
    button.addEventListener('click', async () => {
      await animate(
        '#zen-welcome-title span, #zen-welcome-start-button',
        { opacity: [1, 0], y: [0, -10], filter: ['blur(0px)', 'blur(2px)'] },
        {
          type: 'spring',
          ease: [0.755, 0.05, 0.855, 0.06],
          bounce: 0.4,
          delay: getMotion().stagger(0.4),
        }
      );
      new ZenWelcomePages(getWelcomePages());
    });
  }

  function startZenWelcome() {
    clearBrowserElements();
    initializeZenWelcome();
    animateInitialStage();
  }

  startZenWelcome();
}
