{
  class ZenFolders {
    constructor() {
      this.#initEventListeners();
    }

    #initEventListeners() {
      document.addEventListener('TabGrouped', this.#onTabGrouped.bind(this));
      document.addEventListener('TabUngrouped', this.#onTabUngrouped.bind(this));
      document.addEventListener('TabGroupRemoved', this.#onTabGroupRemoved.bind(this));
    }

    #onTabGrouped(event) {
      const tab = event.target;
      const group = tab.group;
      group.pinned = tab.pinned;
    }

    #onTabUngrouped(event) {}

    #onTabGroupRemoved(event) {}
  }

  window.gZenFolders = new ZenFolders();
}
