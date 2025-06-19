state("Pigface") { }

startup
{
    // Load asl-help binary and instantiate it - will inject code into the asl in the background
    Assembly.Load(File.ReadAllBytes("Components/asl-help")).CreateInstance("Unity");

    //Set the helper to load the scene manager, you probably want this (the helper is set at vars.Helper automagically)
    vars.Helper.LoadSceneManager = true;

    //Setting Game Name and toggling alert to ensure runner is comparing against Game TIme
    vars.Helper.GameName = "PIGFACE";
    vars.Helper.AlertLoadless();

    vars.Watch = (Action<IDictionary<string, object>, IDictionary<string, object>, string>)((oldLookup, currentLookup, key) =>
    {
        // here we see a wild typescript dev attempting C#... oh, the humanity...
        var currentValue = currentLookup.ContainsKey(key) ? (currentLookup[key] ?? "(null)") : null;
        var oldValue = oldLookup.ContainsKey(key) ? (oldLookup[key] ?? "(null)") : null;
        // print if there's a change
        if (oldValue != null && currentValue != null && !oldValue.Equals(currentValue)) {vars.Log(key + ": " + oldValue + " -> " + currentValue);}
        // first iteration, print starting values
        if (oldValue == null && currentValue != null) {vars.Log(key + ": " + currentValue);}
    });

    #region TextComponent
    //Dictionary to cache created/reused layout components by their left-hand label (Text1)
    vars.lcCache = new Dictionary<string, LiveSplit.UI.Components.ILayoutComponent>();
    //Function to set (or update) a text component
    vars.SetText = (Action<string, object>)((text1, text2) =>
{
    const string FileName = "LiveSplit.Text.dll";
    LiveSplit.UI.Components.ILayoutComponent lc;

    //Try to find an existing layout component with matching Text1 (label)
    if (!vars.lcCache.TryGetValue(text1, out lc))
    {
        lc = timer.Layout.LayoutComponents.Reverse().Cast<dynamic>()
            .FirstOrDefault(llc => llc.Path.EndsWith(FileName) && llc.Component.Settings.Text1 == text1)
            ?? LiveSplit.UI.Components.ComponentManager.LoadLayoutComponent(FileName, timer);

        //Cache it for later reference
        vars.lcCache.Add(text1, lc);
    }

    //If it hasn't been added to the layout yet, add it
    if (!timer.Layout.LayoutComponents.Contains(lc))
        timer.Layout.LayoutComponents.Add(lc);

    //Set the label (Text1) and value (Text2) of the text component
    dynamic tc = lc.Component;
    tc.Settings.Text1 = text1;
    tc.Settings.Text2 = text2.ToString();
});

    //Function to remove a single text component by its label
    vars.RemoveText = (Action<string>)(text1 =>
{
    LiveSplit.UI.Components.ILayoutComponent lc;

    //If it's cached, remove it from the layout and the cache
    if (vars.lcCache.TryGetValue(text1, out lc))
    {
        timer.Layout.LayoutComponents.Remove(lc);
        vars.lcCache.Remove(text1);
    }
});

    //Function to remove all text components that were added via this script
    vars.RemoveAllTexts = (Action)(() =>
{
    //Remove each one from the layout
    foreach (var lc in vars.lcCache.Values)
        timer.Layout.LayoutComponents.Remove(lc);

    //Clear the cache
    vars.lcCache.Clear();
});
#endregion

    settings.Add("IL Mode", true, "IL Mode: Enables autostart, autosplit + reset for ILs");

    //Settings group for enabling text display options
    settings.Add("textDisplay", true, "Text Options");
    //Controls whether to automatically clean up text components on script exit
    settings.Add("removeTexts", true, "Remove all texts on exit", "textDisplay");

    //Settings group for game related info
    settings.Add("gameInfo", true, "Various Game Info");
    //Sub-settings: this controls whether to show "some value" as a text component
    settings.Add("placeholder", false, "placeholder", "gameInfo");
    settings.Add("payoutAmount", true, "Amount Paid To Player on Payout Screen", "gameInfo");
    settings.Add("Retry Pressed?", false, "Retry Pressed", "gameInfo");
    settings.Add("totalGameDamage", false, "Total Game Damage", "gameInfo");
    settings.Add("MainObj", true, "Main Obj Count", "gameInfo");
    settings.Add("SideObj", true, "Side Obj Count", "gameInfo");
    settings.Add("footStepTimer", false, "footStepTimer", "gameInfo");

    //Settings group for Unity related info
    settings.Add("UnityInfo", true, "Unity Scene Info");
    //Sub-settings: this controls whether to show "some value" as a text component
    //One downside to this new method is the setting key ie "Scene Loading?" must be the same as text1 (the left text) - a bit weird but not the end of the world.
    settings.Add("Scene Loading?", false, "Check if a Unity scene is loading", "UnityInfo");
    settings.Add("LScene Name: ", false, "Name of Loading Scene", "UnityInfo");
    settings.Add("AScene Name: ", true, "Name of Active Scene", "UnityInfo");

    //Settings group for debug
    settings.Add("DebugInfo", false, "Debug Info");
}

init
{
    vars.RunStarted = false;
    vars.SceneLoading = "";

    //Enable if having scene print issues - a custom function defined in init, the `scene` is the scene's address (e.g. vars.Helper.Scenes.Active.Address)
    vars.ReadSceneName = (Func<IntPtr, string>)(scene => {
    string name = vars.Helper.ReadString(256, ReadStringType.UTF8, scene + 0x38);
    return name == "" ? null : name;
    });

    // This is where we will load custom properties from the code
    vars.Helper.TryLoad = (Func<dynamic, bool>)(mono =>
    {
    vars.Helper["placeholder"] = mono.Make<int>("Cellphone", "Instance", "_ringtone", 0x008);
    vars.Helper["payoutAmount"] = mono.Make<int>("PayoutManager", "Instance", "_payoutAmount");
    vars.Helper["RetryPressed"] = mono.Make<bool>("PlayerInput", "Instance", "playerOptions", "retryButton", "hasSelection");
    vars.Helper["totalGameDamage"] = mono.Make<int>("DataPersistenceManager", "Instance", "gameData", "_totalGameDamage");
    vars.Helper["totalGameKills"] = mono.Make<int>("DataPersistenceManager", "Instance", "gameData", "_totalGameKills");
    vars.Helper["totalDeathCount"] = mono.Make<int>("DataPersistenceManager", "Instance", "gameData", "_totalDeathCount");
    vars.Helper["totalMoney"] = mono.Make<int>("DataPersistenceManager", "Instance", "gameData", "_totalMoney");
    vars.Helper["mainObjectiveCount"] = mono.Make<int>("ObjectiveManager", "Instance", "_mainObjectiveCount");
    vars.Helper["sideObjectiveCount"] = mono.Make<int>("ObjectiveManager", "Instance", "_optionalObjectiveCount");
    vars.Helper["WarehouseCutsceneOneComplete"] = mono.Make<int>("DataPersistenceManager", "Instance", "gameData", "_totalDeathCount"); //NEEDS UPDATE
    vars.Helper["footStepTimer"] = mono.Make<float>("PlayerMovement", "Instance", 0x124);
    return true;
    });

    //Clears errors when scene and other variables are null, will get updated once they get detected
    current.placeholder = 0;
    current.Scene = "";
    current.activeScene = "";
    current.loadingScene = "";
    current.RetryPressed = false;
    current.payoutAmount = 0;
    current.mainObjectiveCount = 9999;
    current.sideObjectiveCount = 9999;
    current.totalGameDamage = 0;
    current.footStepTimer = 0;

//Helper function that sets or removes text depending on whether the setting is enabled - only works in `init` or later because `startup` cannot read setting values
    vars.SetTextIfEnabled = (Action<string, object>)((text1, text2) =>
{
    if (settings[text1])            //If the matching setting is checked
        vars.SetText(text1, text2); //Show the text
    else
        vars.RemoveText(text1);     //Otherwise, remove it
});
}

update
{
    //error handling
    if(current.placeholder == null){current.placeholder = false;}
    if(current.loadingScene == null){current.loadingScene = "null";}
    if(current.activeScene == null){current.activeScene = "null";}
    if(current.payoutAmount == null){current.activeScene = 0;}
    if(current.totalGameDamage == null){current.totalGameDamage = 0;}
    if(current.mainObjectiveCount == null){current.mainObjectiveCount = 9999;}
    if(current.sideObjectiveCount == null){current.sideObjectiveCount = 9999;}
    if(current.footStepTimer == null){current.footStepTimer = 0;}
    
    
    vars.Watch(old, current, "placeholder");
    vars.Watch(old, current, "payoutAmount");
    vars.Watch(old, current, "totalGameDamage");
    vars.Watch(old, current, "RetryPressed");
    vars.Watch(old, current, "mainObjectiveCount");
    vars.Watch(old, current, "sideObjectiveCount");
    vars.Watch(old, current, "footStepTimer");

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

    //Prints various information based on settings selections

    //More text component stuff - checking for setting and then generating the text. No need for .ToString since we do that previously
    vars.SetTextIfEnabled("placeholder",current.placeholder);
    vars.SetTextIfEnabled("payoutAmount",current.payoutAmount);
    vars.SetTextIfEnabled("Scene Loading?",vars.SceneLoading);
    vars.SetTextIfEnabled("LScene Name: ",current.loadingScene);
    vars.SetTextIfEnabled("AScene Name: ",current.activeScene);
    vars.SetTextIfEnabled("Retry Pressed?",current.RetryPressed);
    vars.SetTextIfEnabled("totalGameDamage",current.totalGameDamage);
    vars.SetTextIfEnabled("MainObj",current.mainObjectiveCount);
    vars.SetTextIfEnabled("SideObj",current.sideObjectiveCount);
    vars.SetTextIfEnabled("footStepTimer",current.footStepTimer);
}

start
{
    if
    (
    current.activeScene == "player_warehouse" && old.footStepTimer == 0 && current.footStepTimer > 0 ||
    settings["IL Mode"] && old.mainObjectiveCount == 0 && current.mainObjectiveCount != 0 && current.mainObjectiveCount != -1 && old.activeScene != "intro_cutscene" //IL start, starts when a level is loaded essentially. Count is 0 when "loading" a level, and count is -1 when in apartment
    )   
    {
    vars.RunStarted = true;
    timer.IsGameTimePaused = true;
    return true;
    }
}

onStart
{
    vars.RunStarted = true;
}

split
{
    if
    (
        old.payoutAmount == 0 && current.payoutAmount > 0                          ||
        old.activeScene == "kit_screen" && current.activeScene == "farmhouse"      ||
        settings["IL Mode"] && current.mainObjectiveCount < old.mainObjectiveCount ||
        settings["IL Mode"] && current.sideObjectiveCount < old.sideObjectiveCount
    ) 
    return true;
}

isLoading
{
    return vars.SceneLoading == "Loading" || current.payoutAmount > 0;
}

reset
{
    if(settings["IL Mode"] && old.RetryPressed == false && current.RetryPressed == true)
    {return true;}
}

onReset
{
    vars.RunStarted = false;
}

exit
{
    //Clean up all text components when the script exits
    if (settings["removeTexts"])
    vars.RemoveAllTexts();
}
