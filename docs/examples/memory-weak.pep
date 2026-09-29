var destroyed = 0;

struct Folder {
    var name: String;
    var files: Array<Document>;

    construct(this.name = "") {
        files = Array<Document>();
    }

    destruct {
        destroyed += 1;
    }
}

struct Document {
    var title: String;
    # A weak back pointer: the folder owns its documents, not the other way
    # round, so there is no cycle.
    var folder: Weak<Folder>;

    construct(String title, Folder folder) {
        this.title = title;
        this.folder = Weak<Folder>(folder);
    }

    destruct {
        destroyed += 1;
    }

    String path() {
        with (var f = folder) {
            return f.name + "/" + title;
        } else {
            return "(deleted)/" + title;
        }
        return "";
    }
}

main(): int {
    var kept = Document("draft", Folder("none"));
    {
        var home = Folder("home");
        var notes = Document("notes", home);
        home.files.append(notes);
        assert(notes.path() == "home/notes", "the folder is alive");
        kept = notes;
    }
    # The folder went away with `home`; the weak pointer did not keep it.
    assert(kept.path() == "(deleted)/notes", "the folder is gone");
    assert(kept.folder.expired(), "and the weak reference knows it");
    return 0;
}
