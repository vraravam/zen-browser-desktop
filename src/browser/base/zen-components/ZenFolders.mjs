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

    expandGroupTabs(group) {
      for (const tab of group.tabs) {
        gBrowser.ungroupTab(tab);
      }
    }

    handleTabPin(tab) {
      const group = tab.group;
      if (!group) {
        return false;
      }
      if (group.hasAttribute("split-view-group")) {
        for (const tab of group.tabs) {
          tab.setAttribute("pinned", "true");
        }
        gBrowser.verticalPinnedTabsContainer.insertBefore(group, gBrowser.verticalPinnedTabsContainer.lastChild)
        gBrowser.tabContainer._invalidateCachedTabs();
        return true;
      }
      return false;
    }

    handleTabUnpin(tab) {
      const group = tab.group;
      if (!group) {
        return false;
      }
      if (group.hasAttribute("split-view-group")) {
        for (const tab of group.tabs) {
          tab.removeAttribute("pinned");
        }
        ZenWorkspaces.activeWorkspaceStrip.prepend(group);
        gBrowser.tabContainer._invalidateCachedTabs();
        return true;
      }
      return false;
    }
  }

  window.gZenFolders = new ZenFolders();
}
