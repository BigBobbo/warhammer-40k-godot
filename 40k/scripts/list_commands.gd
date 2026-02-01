extends SceneTree

func _init():
    var dir = DirAccess.open("res://test_results/test_commands/commands")
    if dir:
        dir.list_dir_begin()
        var name = dir.get_next()
        while name != "":
            if !dir.current_is_dir():
                print(name)
            name = dir.get_next()
        dir.list_dir_end()
    else:
        print("failed to open directory")
    quit()
