    state("Pigface") { }

    startup
    {
        // Load asl-help binary and instantiate it - will inject code into the asl in the background
        Assembly.Load(File.ReadAllBytes("Components/asl-help")).CreateInstance("Unity");

        vars.Helper.LoadSceneManager = true;
        vars.SplitCooldownTimer = new Stopwatch();
        vars.Helper.GameName = "PIGFACE";
        vars.Helper.AlertLoadless();

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

    #region setting creation
    dynamic[,] _settings =
    {
        { "SplitOptions",    true,  "Autosplit Options", null },
        { "ObjectiveSplits",    false,  "Objective Splits: Enables autosplits on objective completions", "SplitOptions" },
        { "ApartmentSplits",    true,  "Apartment Splits: Enables a split between contracts", "SplitOptions" },

        { "NG+ Autostart",      false,  "NG+ Autostart - Starts when loading into the apartment", null },
        { "IL Autoreset",       false,  "IL Autoreset - NOTE: will reset timer whenever pressing Retry and upon death", null },

        { "gameInfo",           false,  "Game Info",                    null },
            { "MainObj",        true,  "Main Obj Count",                       "gameInfo" },
            { "SideObj",        true,  "Side Obj Count",                       "gameInfo" },
            { "Health",         true, "Health",                                 "gameInfo" },
            { "totalMoney",     true, "totalMoney",                           "gameInfo" },
            { "totalGameDamage",false, "Total Game Damage",                    "gameInfo" },
            { "payoutAmount",   false,  "Amount Paid To Player on Payout Screen","gameInfo" },
            { "Retry Pressed?", false, "Retry Pressed",                        "gameInfo" },
        { "UnityInfo",          false,  "Unity Scene Info",                     null },
            { "LScene Name: ",  false, "Name of Loading Scene",                "UnityInfo" },
            { "AScene Name: ",  true,  "Name of Active Scene",                 "UnityInfo" },
        { "DebugInfo",          false, "Debug Info",                           null },
            { "placeholder",    false, "placeholder",                          "DebugInfo" },
            { "LastSplit", true, "Last Split Triggered", "DebugInfo" },
    };
    vars.Helper.Settings.Create(_settings);
    #endregion
    }

    init
    {
        vars.SceneLoading = "";
        vars.SplitCooldownTimer.Start();
        vars.TriggeredLevels = new HashSet<string>();
        vars.LastTriggeredSplit = "N/A";

        vars.LevelChecks = new List<Tuple<string, Func<dynamic, dynamic, bool>>> 
        {
            Tuple.Create("Warehouse", (Func<dynamic, dynamic, bool>)((o, c) => !o.warComp && c.warComp)),
            Tuple.Create("Farmhouse", (Func<dynamic, dynamic, bool>)((o, c) => !o.farComp && c.farComp)),
            Tuple.Create("Sunset Motel", (Func<dynamic, dynamic, bool>)((o, c) => !o.sunComp && c.sunComp)),
            Tuple.Create("Train Station", (Func<dynamic, dynamic, bool>)((o, c) => !o.traComp && c.traComp)),
            Tuple.Create("Suburbs", (Func<dynamic, dynamic, bool>)((o, c) => !o.subComp && c.subComp)),
            Tuple.Create("Abandoned Mall", (Func<dynamic, dynamic, bool>)((o, c) => !o.mallComp && c.mallComp)),
            Tuple.Create("Prison Night Club", (Func<dynamic, dynamic, bool>)((o, c) => !o.priComp && c.priComp))
        };

        //Enable if having scene print issues - a custom function defined in init, the `scene` is the scene's address (e.g. vars.Helper.Scenes.Active.Address)
        vars.ReadSceneName = (Func<IntPtr, string>)(scene => {
        string name = vars.Helper.ReadString(256, ReadStringType.UTF8, scene + 0x38);
        return name == "" ? null : name;
        });

        // This is where we will load custom properties from the code
        vars.Helper.TryLoad = (Func<dynamic, bool>)(mono =>
        {
        vars.Helper["placeholder"] = mono.Make<float>("PlayerController", "Instance", 0x0b4);
        vars.Helper["Health"] = mono.Make<float>("PlayerHealth", "Instance", "_currentHealth");
        vars.Helper["mainObjectiveCount"] = mono.Make<int>("ObjectiveManager", "Instance", "_mainObjectiveCount");
        vars.Helper["sideObjectiveCount"] = mono.Make<int>("ObjectiveManager", "Instance", "_optionalObjectiveCount");
        vars.Helper["payoutAmount"] = mono.Make<int>("PayoutManager", "Instance", "_payoutAmount");
        vars.Helper["RetryPressed"] = mono.Make<bool>("PlayerInput", "Instance", "playerOptions", "retryButton", "hasSelection");
        vars.Helper["totalGameDamage"] = mono.Make<int>("DataPersistenceManager", "Instance", "gameData", "_totalGameDamage");
        vars.Helper["totalGameKills"] = mono.Make<int>("DataPersistenceManager", "Instance", "gameData", "_totalGameKills");
        vars.Helper["totalDeathCount"] = mono.Make<int>("DataPersistenceManager", "Instance", "gameData", "_totalDeathCount");
        vars.Helper["totalMoney"] = mono.Make<int>("DataPersistenceManager", "Instance", "gameData", "_totalMoney");

        vars.Helper["warComp"] = mono.Make<bool>("DataPersistenceManager", "Instance", "gameData", "_warehouseCompleted");
        vars.Helper["farComp"] = mono.Make<bool>("DataPersistenceManager", "Instance", "gameData", "_farmhouseCompleted");
        vars.Helper["sunComp"] = mono.Make<bool>("DataPersistenceManager", "Instance", "gameData", "_sunsetMotelCompleted");
        vars.Helper["traComp"] = mono.Make<bool>("DataPersistenceManager", "Instance", "gameData", "_trainStationCompleted");
        vars.Helper["subComp"] = mono.Make<bool>("DataPersistenceManager", "Instance", "gameData", "_suburbsCompleted");
        vars.Helper["mallComp"] = mono.Make<bool>("DataPersistenceManager", "Instance", "gameData", "_abandonedMallCompleted");
        vars.Helper["priComp"] = mono.Make<bool>("DataPersistenceManager", "Instance", "gameData", "_prisonNightClubCompleted");
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
        current.totalMoney = 0;
        current.warComp = false;
        current.farComp = false;
        current.sunComp = false;
        current.traComp = false;
        current.subComp = false;
        current.mallComp = false;
        current.priComp = false;

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
        vars.Helper.Update();
		vars.Helper.MapPointers();

        //Get the current active scene's name and set it to `current.activeScene` - sometimes, it is null, so fallback to old value
        current.activeScene = vars.Helper.Scenes.Active.Name ?? current.activeScene;
        //Usually the scene that's loading, a bit jank in this version of asl-help
        current.loadingScene = vars.Helper.Scenes.Loaded[0].Name ?? current.loadingScene;
        if(!String.IsNullOrWhiteSpace(vars.Helper.Scenes.Active.Name))    current.activeScene = vars.Helper.Scenes.Active.Name;
        if(!String.IsNullOrWhiteSpace(vars.Helper.Scenes.Loaded[0].Name))    current.loadingScene = vars.Helper.Scenes.Loaded[0].Name;
        //Log changes to the active scene
        if(old.activeScene != current.activeScene) {vars.Log("activeScene: " + old.activeScene + " -> " + current.activeScene);}
        if(old.loadingScene != current.loadingScene) {vars.Log("loadingScene: " + old.loadingScene + " -> " + current.loadingScene);}

        //More text component stuff - checking for setting and then generating the text. No need for .ToString since we do that previously
        vars.SetTextIfEnabled("placeholder",current.placeholder);
        vars.SetTextIfEnabled("payoutAmount",current.payoutAmount);
        vars.SetTextIfEnabled("LScene Name: ",current.loadingScene);
        vars.SetTextIfEnabled("AScene Name: ",current.activeScene);
        vars.SetTextIfEnabled("Retry Pressed?",current.RetryPressed);
        vars.SetTextIfEnabled("totalGameDamage",current.totalGameDamage);
        vars.SetTextIfEnabled("totalMoney",current.totalMoney);
        vars.SetTextIfEnabled("Health",current.Health);
        vars.SetTextIfEnabled("MainObj",current.mainObjectiveCount);
        vars.SetTextIfEnabled("SideObj",current.sideObjectiveCount);
        vars.SetTextIfEnabled("LastSplit", vars.LastTriggeredSplit);
    }

    start
    {
        //Starts when a level is loaded essentially. Count is 0 when "loading" a level, and count is -1 when in apartment or intro cutscene
        if
        ( 
        (settings["NG+ Autostart"] && old.activeScene != "player_apt" && current.activeScene == "player_apt") ||
		(old.Health == 0 && current.Health == 100 && current.activeScene != "intro_cutscene")
        )
        {return true;}

        
    }

    onStart
    {
        vars.TriggeredLevels.Clear();
        vars.SplitCooldownTimer.Restart();
    }

    split
    {
        if(vars.SplitCooldownTimer.Elapsed.TotalSeconds < 3) {return false;}

        //Level Splits
        foreach (var check in vars.LevelChecks)
        {
            if (check.Item2(old, current) && !vars.TriggeredLevels.Contains(check.Item1))
            {
                vars.LastTriggeredSplit = check.Item1 + " Completed";
                vars.TriggeredLevels.Add(check.Item1); // mark as fired
                vars.SplitCooldownTimer.Restart();
                return true;
            }
        }
        //Objective Splits
        if(settings["ApartmentSplits"])
        {
            if (old.activeScene == "kit_screen" && current.activeScene != "kit_screen")
            {
                vars.SplitCooldownTimer.Restart();
                return true;
            }
        }
        //Objective Splits
        if(settings["ObjectiveSplits"])
        {
            if (current.mainObjectiveCount < old.mainObjectiveCount && current.mainObjectiveCount != -1 ||
                current.sideObjectiveCount < old.sideObjectiveCount && current.sideObjectiveCount != -1)
            {
                vars.SplitCooldownTimer.Restart();
                return true;
            }
        }
    }

    isLoading
    {
        return current.loadingScene != current.activeScene || (current.Health <= 0 && current.activeScene != "player_apt");
    }

    reset
    {
        if
        (
            (settings["IL Autoreset"] && old.RetryPressed == false && current.RetryPressed == true) ||
            (settings["IL Autoreset"] && old.Health > 0 && current.Health <= 0)
        )
        {return true;}
    }

    onReset
    {
        vars.TriggeredLevels.Clear();
    }
