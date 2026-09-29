// Version picker for the versioned site built by `pepper-docgen build`:
// every version of the book lives in its own folder beside versions.json.
(function () {
    "use strict";
    if (typeof path_to_root === "undefined") {
        return;
    }
    // The book's root folder (e.g. https://host/pepper/0.1.0/) and the site
    // root above it, where versions.json lives.
    var bookRoot = new URL(path_to_root || "./", window.location.href);
    var siteRoot = new URL("../", bookRoot);
    var current = decodeURIComponent(bookRoot.pathname.replace(/\/$/, "").split("/").pop());
    var page = window.location.href.slice(bookRoot.href.length);

    fetch(new URL("versions.json", siteRoot))
        .then(function (response) { return response.ok ? response.json() : null; })
        .then(function (data) {
            if (!data || !data.versions || data.versions.length === 0) {
                return;
            }
            var select = document.createElement("select");
            select.className = "version-switcher";
            select.title = "Documentation version";
            select.setAttribute("aria-label", "Documentation version");
            data.versions.forEach(function (version) {
                var option = document.createElement("option");
                option.value = version;
                option.textContent = version === data.latest ? version + " (latest)" : version;
                option.selected = version === current;
                select.appendChild(option);
            });
            select.addEventListener("change", function () {
                // The same page in the other version, if it has it; its
                // 404 page otherwise links back to the start.
                window.location.href = new URL(select.value + "/" + page, siteRoot).href;
            });
            var buttons = document.querySelector(".right-buttons");
            if (buttons) {
                buttons.insertBefore(select, buttons.firstChild);
            }
        })
        .catch(function () { /* served without a versioned site: no picker */ });
})();
