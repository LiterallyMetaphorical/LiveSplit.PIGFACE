state("Pigface") { }

init
{
    vars.startTimeOffset = 0.191;
    vars.runnerRetryStarted = false;

    //helps clear some errors when scene is null
    current.Scene = "SceneManager Not Initialized";
    current.activeScene = "SceneManager Not Initialized";
    current.loadingScene = "SceneManager Not Initialized";
    current.RetryPressed = false;
    current.mainObjectiveCount = 0;
    current.objectivePrint = 0;

    // This is where we will load custom properties from the code, EMPTY FOR NOW
    vars.Helper.TryLoad = (Func<dynamic, bool>)(mono =>
    {
    vars.Helper["RetryPressed"] = mono.Make<bool>("PlayerInput", "Instance", "playerOptions", "retryButton", "hasSelection");
    vars.Helper["mainObjectiveCount"] = mono.Make<int>("ObjectiveManager", "Instance", "_mainObjectiveCount");
    vars.Helper["sideObjectiveCount"] = mono.Make<int>("ObjectiveManager", "Instance", "_optionalObjectiveCount");
    vars.Helper["objectives"] = mono.MakeList<int>("ObjectiveManager", "Instance", "_playerCellphone", "_objectives");
    return true;
    });

    //Enable if having scene print issues - a custom function defined in init, the `scene` is the scene's address (e.g. vars.Helper.Scenes.Active.Address)
    vars.ReadSceneName = (Func<IntPtr, string>)(scene => {
    string name = vars.Helper.ReadString(256, ReadStringType.UTF8, scene + 0x38);
    return name == "" ? null : name;
    });
}

startup
{
    // Load asl-help binary and instantiate it - will inject code into the asl in the background
    Assembly.Load(File.ReadAllBytes("Components/asl-help")).CreateInstance("Unity");

    //Set the helper to load the scene manager, you probably want this (the helper is set at vars.Helper automagically)
    vars.Helper.LoadSceneManager = true;

    //Setting Game Name and toggling alert to ensure runner is comparing against Game TIme
    vars.Helper.GameName = "PIGFACE";
    vars.Helper.AlertLoadless();

    vars.SceneLoading = "";

    #region debugging
    vars.Watch = (Action<IDictionary<string, object>, IDictionary<string, object>, string>)((oldLookup, currentLookup, key) =>
    {
        // here we see a wild typescript dev attempting C#... oh, the humanity...
        var currentValue = currentLookup.ContainsKey(key) ? (currentLookup[key] ?? "(null)") : null;
        var oldValue = oldLookup.ContainsKey(key) ? (oldLookup[key] ?? "(null)") : null;

        // print if there's a change
        if (oldValue != null && currentValue != null && !oldValue.Equals(currentValue)) {
            vars.Log(key + ": " + oldValue + " -> " + currentValue);
        }

        // first iteration, print starting values
        if (oldValue == null && currentValue != null) {
            vars.Log(key + ": " + currentValue);
        }
    });

    //creates text components for variable information
	vars.SetTextComponent = (Action<string, string>)((id, text) =>
	{
	var textSettings = timer.Layout.Components.Where(x => x.GetType().Name == "TextComponent").Select(x => x.GetType().GetProperty("Settings").GetValue(x, null));
	var textSetting = textSettings.FirstOrDefault(x => (x.GetType().GetProperty("Text1").GetValue(x, null) as string) == id);
	if (textSetting == null)
	    {
            var textComponentAssembly = Assembly.LoadFrom("Components\\LiveSplit.Text.dll");
            var textComponent = Activator.CreateInstance(textComponentAssembly.GetType("LiveSplit.UI.Components.TextComponent"), timer);
            timer.Layout.LayoutComponents.Add(new LiveSplit.UI.Components.LayoutComponent("LiveSplit.Text.dll", textComponent as LiveSplit.UI.Components.IComponent));
            textSetting = textComponent.GetType().GetProperty("Settings", BindingFlags.Instance | BindingFlags.Public).GetValue(textComponent, null);
            textSetting.GetType().GetProperty("Text1").SetValue(textSetting, id);
	    }
	textSetting.GetType().GetProperty("Text2").SetValue(textSetting, text);
    });
	#endregion

    settings.Add("IL Mode", true, "IL Mode: IL Based autosplitting & enable reset on Retry");

    //Parent setting
	settings.Add("Variable Information", true, "Variable Information");

	//Child settings that will sit beneath Parent setting
    settings.Add("Retry Pressed", false, "Retry Pressed", "Variable Information");
    settings.Add("MainObj", true, "Main Obj Count", "Variable Information");
    settings.Add("SideObj", true, "Side Obj Count", "Variable Information");

    settings.Add("Unity Scene Info", false, "Unity Scene Info", "Variable Information");
    settings.Add("Unity Scene Loading", false, "Unity Scene Loading", "Unity Scene Info");
    settings.Add("Loading Scene Name", false, "Loading Scene Name", "Unity Scene Info");
    settings.Add("Active Scene Name", false, "Active Scene Name", "Unity Scene Info");
}

onStart
{
    vars.Log("activeScene: " + current.activeScene);
    vars.Log("loadingScene: " + current.loadingScene);
}

update
{
    vars.Watch(old, current, "RetryPressed");
    vars.Watch(old, current, "mainObjectiveCount");
    vars.Watch(old, current, "sideObjectiveCount");

    //Trying to handle errors, idk why but subregion seems to be particularly bad
    if (current.mainObjectiveCount == null) {current.mainObjectiveCount = 0;}

    //Get the current active scene's name and set it to `current.activeScene` - sometimes, it is null, so fallback to old value
    current.activeScene = vars.Helper.Scenes.Active.Name ?? current.activeScene;

    //Usually the scene that's loading, a bit jank in this version of asl-help
    current.loadingScene = vars.Helper.Scenes.Loaded[0].Name ?? current.loadingScene;

    //Log changes to the active scene
    if(old.activeScene != current.activeScene) {vars.Log("activeScene: " + old.activeScene + " -> " + current.activeScene);}
    if(old.loadingScene != current.loadingScene) {vars.Log("loadingScene: " + old.loadingScene + " -> " + current.loadingScene);}

    //Setting up for load removal & text display of load removal stuff
    if(old.loadingScene != current.loadingScene){vars.SceneLoading = "Loading";}
    if(old.activeScene != current.activeScene){vars.SceneLoading = "Not Loading";}

    //Setting up for IL Mode Retry Time Offset
    if(old.RetryPressed == false && current.RetryPressed == true){vars.runnerRetryStarted = true;}

    //Prints various information based on settings selections
    if(settings["Unity Scene Loading"]){vars.SetTextComponent("Scene Loading?",vars.SceneLoading.ToString());}
    if(settings["Loading Scene Name"]){vars.SetTextComponent("LScene Name: ",current.loadingScene.ToString());}
    if(settings["Active Scene Name"]){vars.SetTextComponent("AScene Name: ",current.activeScene.ToString());}
    if(settings["Retry Pressed"]){vars.SetTextComponent("Retry Pressed?",current.RetryPressed.ToString());}
    if(settings["MainObj"]){vars.SetTextComponent("Main Obj: ",current.mainObjectiveCount.ToString());}
    if(settings["SideObj"]){vars.SetTextComponent("Side Obj: ",current.sideObjectiveCount.ToString());}
}

start
{
    if
    (
    old.mainObjectiveCount == 0 && current.mainObjectiveCount != 0 && current.mainObjectiveCount != -1 || //IL start, starts when a level is loaded essentially. Count is 0 when "loading" a level, and count is -1 when in apartment
    old.mainObjectiveCount == -1 && current.mainObjectiveCount != 0 && current.mainObjectiveCount != -1 //maybe unecessary, but just a redunandcy cause of my lack of testing.
    )   
    {
    timer.IsGameTimePaused = true;
    return true;
    }
}


split
{
    if
    (
    (current.activeScene == "player_warehouse" && current.loadingScene == "player_apt" && old.loadingScene == "player_warehouse") || //split after Warehouse level in FG
    (current.activeScene == "kit_screen"       && current.loadingScene == "farmhouse" && old.loadingScene == "kit_screen")        || //split after apartment + kit prep entering Farmhouse in FG
    (current.activeScene == "farmhouse"        && current.loadingScene == "outro_cutscene" && old.loadingScene == "farmhouse")    || // split after Farmhouse level in FG
    (settings["IL Mode"] && current.activeScene == "farmhouse" && current.loadingScene == "player_apt" && old.loadingScene == "farmhouse") || // split after Farmhouse level in IL
    (settings["IL Mode"] && current.activeScene == "player_warehouse" && current.loadingScene == "player_apt" && old.loadingScene == "player_warehouse")    // split after Warehouse level in IL
    )      
    return true;
}

isLoading
{
    return vars.SceneLoading == "Loading";
}

reset
{
    if(settings["IL Mode"] && old.RetryPressed == false && current.RetryPressed == true)
    {return true;}
}