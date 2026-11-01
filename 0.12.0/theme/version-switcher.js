// Version picker for the versioned site built by `pep-doc build`:
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
            select.setAttribute("aria-label", "Documentation version");
            data.versions.forEach(function (version) {
                var option = document.createElement("option");
                option.value = version;
                option.textContent = version === data.latest ? version + " (latest)" : version;
                option.selected = version === current;
                select.appendChild(option);
            });
            // Read as the select's description, since aria-label names it.
            select.title = "Press Enter to open the chosen version";
            // The same page in the chosen version, or its introduction when
            // that version has no such page.
            function go() {
                if (select.value === current) {
                    return;
                }
                var target = new URL(select.value + "/" + page, siteRoot).href;
                var start = new URL(select.value + "/", siteRoot).href;
                fetch(target, { method: "HEAD" })
                    .then(function (response) { return response.ok ? target : start; })
                    .catch(function () { return start; })
                    .then(function (url) { window.location.href = url; });
            }
            // Arrow keys on a closed select fire `change` in Chrome and Edge,
            // so a keyboard choice waits for Enter (WCAG 3.2.2); a pointer
            // choice goes at once.
            var byKeyboard = false;
            select.addEventListener("pointerdown", function () { byKeyboard = false; });
            select.addEventListener("keydown", function (event) {
                byKeyboard = true;
                if (event.key === "Enter") {
                    event.preventDefault();
                    go();
                }
            });
            // A keyboard choice left without Enter is dropped.
            select.addEventListener("blur", function () { select.value = current; });
            select.addEventListener("change", function () {
                if (!byKeyboard) {
                    go();
                }
            });
            var buttons = document.querySelector(".right-buttons");
            if (buttons) {
                buttons.insertBefore(select, buttons.firstChild);
            }
        })
        .catch(function () { /* served without a versioned site: no picker */ });
})();
