package states;

// If you want to add your stage to the game, copy states/stages/Template.hx,
// and put your stage code there, then, on PlayState, search for
// "switch (curStage)", and add your stage to that list.

// If you want to code Events, you can either code it on a Stage file or on PlayState, if you're doing the latter, search for:
// "function eventPushed" - Only called *one time* when the game loads, use it for precaching events that use the same assets, no matter the values
// "function eventPushedUnique" - Called one time per event, use it for precaching events that uses different assets based on its values
// "function eventEarlyTrigger" - Used for making your event start a few MILLISECONDS earlier
// "function triggerEvent" - Called when the song hits your event's timestamp, this is probably what you were looking for

import online.substates.PostTextSubstate;
import haxe.crypto.Md5;
import online.network.FunkinNetwork;
import online.objects.InputText;
import online.replay.ReplayRecorder.ReplayData;
import online.replay.*;
import openfl.geom.Point;
import openfl.geom.Rectangle;
import openfl.Lib;
import flixel.util.FlxSpriteUtil;
import flixel.group.FlxGroup;
import flixel.addons.util.FlxAsyncLoop;
import flixel.effects.FlxFlicker;
import online.objects.LeavePie;
import online.objects.ChatBox;
import online.gui.LoadingScreen;
import online.gui.Alert;
import online.backend.Waiter;
import online.states.RoomState;
import online.GameClient;
import online.objects.NicommentsView;
import backend.Achievements;
import backend.Highscore;
import backend.StageData;
import backend.WeekData;
import backend.Song;
import backend.Section;
import backend.Rating;

import flixel.FlxBasic;
import flixel.FlxObject;
import flixel.FlxSubState;
import flixel.addons.transition.FlxTransitionableState;
import flixel.math.FlxPoint;
import flixel.util.FlxSort;
import flixel.util.FlxStringUtil;
import flixel.util.FlxSave;
import flixel.input.keyboard.FlxKey;
import flixel.animation.FlxAnimationController;
import lime.utils.Assets;
import openfl.utils.Assets as OpenFlAssets;
import openfl.events.KeyboardEvent;
import tjson.TJSON as Json;

import cutscenes.CutsceneHandler;
import cutscenes.DialogueBoxPsych;

import states.StoryMenuState;
import states.FreeplayState;
import states.editors.ChartingState;
import states.editors.CharacterEditorState;

import substates.PauseSubState;
import substates.GameOverSubstate;

#if !flash 
import flixel.addons.display.FlxRuntimeShader;
import openfl.filters.ShaderFilter;
#end

#if sys
import sys.FileSystem;
import sys.io.File;
#end

#if VIDEOS_ALLOWED 
#if hxCodec
#if (hxCodec >= "3.0.0") import hxcodec.flixel.FlxVideo as VideoHandler;
#elseif (hxCodec >= "2.6.1") import hxcodec.VideoHandler as VideoHandler;
#elseif (hxCodec == "2.6.0") import VideoHandler;
#else import vlc.MP4Handler as VideoHandler; #end
#end
#end

import objects.Note.EventNote;
import objects.*;
import states.stages.objects.*;

#if LUA_ALLOWED
import psychlua.*;
#else
import psychlua.FunkinLua;
import psychlua.LuaUtils;
import psychlua.HScript;
#end

#if HSCRIPT_ALLOWED
import tea.SScript;
#end

class PlayState extends MusicBeatState
{
	public static var STRUM_X = 42;
	public static var STRUM_X_MIDDLESCROLL = -278;

	public static var ratingStuff:Array<Dynamic> = [
		['You Suck!', 0.2], //From 0% to 19%
		['Shit', 0.4], //From 20% to 39%
		['Bad', 0.5], //From 40% to 49%
		['Bruh', 0.6], //From 50% to 59%
		['Meh', 0.69], //From 60% to 68%
		['Nice', 0.7], //69%
		['Good', 0.8], //From 70% to 79%
		['Great', 0.9], //From 80% to 89%
		['Sick!', 1], //From 90% to 99%
		['Perfect!!', 1] //The value on this one isn't used actually, since Perfect is always "1"
	];

	//event variables
	private var isCameraOnForcedPos:Bool = false;

	public var boyfriendMap:Map<String, Character> = new Map<String, Character>();
	public var dadMap:Map<String, Character> = new Map<String, Character>();
	public var gfMap:Map<String, Character> = new Map<String, Character>();
	public var variables:Map<String, Dynamic> = new Map<String, Dynamic>();
	
	#if HSCRIPT_ALLOWED
	public var hscriptArray:Array<HScript> = [];
	#end

	#if LUA_ALLOWED
	public var modchartTweens:Map<String, FlxTween> = new Map<String, FlxTween>();
	public var modchartSprites:Map<String, FlxSprite> = new Map<String, FlxSprite>();
	public var modchartTimers:Map<String, FlxTimer> = new Map<String, FlxTimer>();
	public var modchartSounds:Map<String, FlxSound> = new Map<String, FlxSound>();
	public var modchartTexts:Map<String, FlxText> = new Map<String, FlxText>();
	public var modchartSaves:Map<String, FlxSave> = new Map<String, FlxSave>();
	#end

	public var BF_X:Float = 770;
	public var BF_Y:Float = 100;
	public var DAD_X:Float = 100;
	public var DAD_Y:Float = 100;
	public var GF_X:Float = 400;
	public var GF_Y:Float = 130;

	public var songSpeedTween:FlxTween;
	public var songSpeed(default, set):Float = 1;
	public var songSpeedType:String = "multiplicative";
	public var noteKillOffset:Float = 350;

	public var playbackRate(default, set):Float = 1;

	public static var opponentMode:Bool = false;

	public var boyfriendGroup:FlxSpriteGroup;
	public var dadGroup:FlxSpriteGroup;
	public var gfGroup:FlxSpriteGroup;
	public static var curStage:String = '';
	public static var stageUI:String = "normal";
	public static var isPixelStage(get, never):Bool;

	@:noCompletion
	static function get_isPixelStage():Bool
		return stageUI == "pixel";

	public static var SONG(default, null):SwagSong;

	public static function loadSong(jsonInput:String, ?folder:String):SwagSong {
		RAW_SONG = Song.loadRawSong(jsonInput, folder);
		return SONG = Song.parseRawJSON(jsonInput, RAW_SONG);
	}

	public static function loadSongFromSwag(v:SwagSong):SwagSong {
		RAW_SONG = haxe.Json.stringify(v);
		return SONG = Song.parseRawJSON('', RAW_SONG);
	}
	
	public static var RAW_SONG:String = '';
	public static var isStoryMode:Bool = false;
	public static var storyWeek:Int = 0;
	public static var storyPlaylist:Array<String> = [];
	public static var storyDifficulty:Int = 1;
	public static var isErect:Bool = false;

	public var songSuffix(default, set):String = '';
	function set_songSuffix(v) {
		songSuffix = "";
		if (v.trim().length > 0 && !v.startsWith("-"))
			songSuffix += "-";
		songSuffix += v;
		return songSuffix;
	}

	public var spawnTime:Float = 2000;

	public var vocals:FlxSound;
	public var opponentVocals:FlxSound;
	public var inst:FlxSound;

	public var dad:Character = null;
	public var gf:Character = null;
	public var boyfriend:Character = null;

	public var notes:FlxTypedGroup<Note>;
	public var unspawnNotes:Array<Note> = [];
	public var eventNotes:Array<EventNote> = [];

	public var camFollow:FlxObject;
	private static var prevCamFollow:FlxObject;

	public var strumLineNotes:FlxTypedGroup<StrumNote>;
	public var opponentStrums:FlxTypedGroup<StrumNote>;
	public var playerStrums:FlxTypedGroup<StrumNote>;
	public var grpHoldSplashes:FlxTypedGroup<SustainSplash>;
	public var grpNoteSplashes:FlxTypedGroup<NoteSplash>;

	public var abot:ABotSpeaker;

	public var camZooming:Bool = false;
	public var camZoomingMult:Float = 1;
	public var camZoomingDecay:Float = 1;

	public static final DEFAULT_BOP_INTENSITY:Float = 1.015;
	public static final DEFAULT_ZOOM_RATE:Int = 4;

	public var cameraBopIntensity:Float = DEFAULT_BOP_INTENSITY;
	public var hudCameraZoomIntensity:Float = 0.015 * 2.0;
	public var cameraZoomRate:Int = DEFAULT_ZOOM_RATE;

	private var curSong:String = "";

	public var gfSpeed:Int = 1;
	var _health:Float = 1;
	var _prevOHealth:Float = 1;
	public var health(get, set):Float;
	function get_health() {
		if (GameClient.isConnected()) {
			if (_prevOHealth != GameClient.room.state.health && gf != null)
				gf.onHealth(_prevOHealth, GameClient.room.state.health);

			return _prevOHealth = GameClient.room.state.health;
		}
		return _health;
	}
	function set_health(v) {
		if (gf != null)
			gf.onHealth(_health, v);

		if (GameClient.isConnected()) {
			return GameClient.room.state.health;
		}
		return _health = v;
	}

	public var maxCombo:Int = 0;
	function set_combo(v:Int):Int {
		if (gf != null)
			gf.onCombo(combo, v);
		maxCombo = Math.floor(Math.max(maxCombo, v));
		return combo = v;
	}
	public var combo(default, set):Int = 0;

	public var healthBar:HealthBar;
	public var timeBar:HealthBar;
	var songPercent:Float = 0;

	public var ratingsData:Array<Rating> = Rating.loadDefault();
	public var fullComboFunction:Void->Void = null;

	private var generatedMusic:Bool = false;
	public var endingSong:Bool = false;
	public var startingSong:Bool = false;
	private var updateTime:Bool = true;
	public static var changedDifficulty:Bool = false;
	public static var chartingMode:Bool = false;

	//Gameplay settings
	public var healthGain:Float = 1;
	public var healthLoss:Float = 1;
	public var instakillOnMiss:Bool = false;
	public var cpuControlled(default, set):Bool = false;
	function set_cpuControlled(v):Bool {
		if (GameClient.isConnected()) {
			if (cpuControlled)
				return cpuControlled;

			if (v)
				GameClient.send("botplay");
		}

		cpuControlled = v;
		showBotplay();
		return cpuControlled;
	}
	public var practiceMode:Bool = false;
	public var noBadNotes:Bool = false;

	public var botplaySine:Float = 0;
	public var botplayTxt:FlxText;

	public var iconP1:HealthIcon;
	public var iconP2:HealthIcon;
	public var camHUD:FlxCamera;
	public var camGame:FlxCamera;
	public var camOther:FlxCamera;
	public var camLoading:FlxCamera;
	public var luaTpadCam:FlxCamera;
	public var cameraSpeed:Float = 1;

	var _tempDiff:Float = 0;
	public var songScore(default, set):Int = 0;
	function set_songScore(v) {
		_tempDiff = v - songScore;
		//_tempDiff *= 1 + (playbackRate - 1) * 0.1;
		//_tempDiff *= 1 + (songSpeed - PlayState.SONG.speed) * 0.1;
		_tempDiff *= 1 + Math.max(0, combo - 1) * 0.001;
		return songScore += Math.floor(_tempDiff);
	}
	public var songHits:Int = 0;
	public var songMisses:Int = 0;
	public var songSicks:Int = 0;
	public var songGoods:Int = 0;
	public var songBads:Int = 0;
	public var songShits:Int = 0;
	public var songPoints:Float = 0;

	public var pointsPercent:Float = 0;

	static var COLOR_SICK:FlxColor = 0x6CFD8E;
	static var COLOR_GOOD:FlxColor = 0x68D5FD;
	static var COLOR_BAD:FlxColor = 0xFCD768;
	static var COLOR_SHIT:FlxColor = 0xFC6B68;

	public var scoreTxt:FlxText;
	public var scoreTxtP1:FlxText;
	public var scoreTxtP2:FlxText;
	var timeTxt:FlxText;
	var scoreTxtTween:FlxTween;

	public static var campaignScore:Int = 0;
	public static var campaignMisses:Int = 0;
	public static var seenCutscene:Bool = false;
	public static var deathCounter:Int = 0;

	public var defaultCamZoom:Float = 1.05;
	public var defaultHUDCamZoom:Float = 1;
	public var forceCameraZoom(get, set):Float;
	function get_forceCameraZoom() {
		return defaultCamZoom;
	}
	function set_forceCameraZoom(v) {
		FlxG.camera.zoom = v;
		defaultCamZoom = v;
		return v;
	}

	public var currentCameraX(get, set):Float;
	function get_currentCameraX() {
		return camFollow.x;
	}
	function set_currentCameraX(v) {
		FlxG.camera.scroll.x = v;
		camFollow.x = v;
		return v;
	}

	public var currentCameraY(get, set):Float;
	function get_currentCameraY() {
		return camFollow.y;
	}
	function set_currentCameraY(v) {
		FlxG.camera.scroll.y = v;
		camFollow.y = v;
		return v;
	}

	// how big to stretch the pixel art assets
	public static var daPixelZoom:Float = 6;
	private var singAnimations:Array<String> = ['singLEFT', 'singDOWN', 'singUP', 'singRIGHT'];

	public var inCutscene:Bool = false;
	public var skipCountdown:Bool = false;
	var songLength:Float = 0;

	public var boyfriendCameraOffset:Array<Float> = null;
	public var opponentCameraOffset:Array<Float> = null;
	public var girlfriendCameraOffset:Array<Float> = null;

	#if DISCORD_ALLOWED
	// Discord RPC variables
	var storyDifficultyText:String = "";
	var detailsText:String = "";
	var detailsPausedText:String = "";
	#end

	//Achievement shit
	var keysPressed:Array<Int> = [];
	var boyfriendIdleTime:Float = 0.0;
	var boyfriendIdled:Bool = false;

	// uh... check if opponent is holding
	public var playerHold(default, set):Bool = false;
	public var oppHold:Bool = false;

	// Lua shit
	public static var instance:PlayState;
	public var luaArray:Array<FunkinLua> = [];
	#if LUA_ALLOWED
	private var luaDebugGroup:FlxTypedGroup<DebugLuaText>;
	#end
	public var introSoundsSuffix:String = '';
	public var skinsSuffix:String = '';

	// Less laggy controls
	private var keysArray:Array<String>;

	public var precacheList:Map<String, String> = new Map<String, String>();
	public var songName:String;

	// Callbacks for stages
	public var startCallback:Void->Void = null;
	public var endCallback:Void->Void = null;

	var chatBox:ChatBox;
	var leavePie:LeavePie;

	static var swingMode:Bool = false;

	function canInput() {
		if (chatBox != null && chatBox.focused) {
			return false;
		}
		return true;
	}

	function set_playerHold(v) {
		if (playerHold != v) {
			playerHold = v;
			GameClient.send("noteHold", v);
		}
		return v;
	}

	var freakyFlicker:FlxFlicker;
	var readyTween:FlxTween;
	var waitReady(default, set) = false;
	var isReady = false;
	var canStart = true;
	function set_waitReady(v) {
		if (readyTween != null)
			readyTween.cancel();
		if (freakyFlicker?.timer != null)
			freakyFlicker.stop();

		if (waitReadySpr != null)
			readyTween = FlxTween.tween(waitReadySpr, {alpha: v ? 1 : 0}, 0.5, {ease: FlxEase.quadIn});

		paused = v;

		return waitReady = v;
	}
	var waitReadySpr:Alphabet;

	public var songDensity:Float = 0;

	var stageData:StageFile;
	var stageModDir:String;
	var oldModDir:String;
	var showTime:Bool;
	var camPos:FlxPoint;
	var asyncLoop:FlxAsyncLoop;
	var isCreated:Bool = false;
	var stageExists:Bool = false;
	public static var orderOffset:Int = 0;

	public static var replayData(default, set):ReplayData;
	public static var replayID:String = null;
	static function set_replayData(v) {
		replayID = null;
		return replayData = v;
	}
	public var replayRecorder:ReplayRecorder;
	public var replayPlayer:ReplayPlayer;
	public var nicomments:NicommentsView;
	
	public var songId:String = null;

	@:unreflective
	public static var redditMod:Bool = false;

	public var luaTouchPad:TouchPad;

	override public function create()
	{
		theWorld = true;

		Conductor.judgeSongPosition = null;
		Conductor.judgePlaybackRate = null;

		if (GameClient.isConnected()) {
			Lib.application.window.resizable = false;
			swingMode = false;
		}

		Paths.clearStoredMemory();

		// var gameCam:FlxCamera = FlxG.camera;
		camGame = new FlxCamera();
		camHUD = new FlxCamera();
		camOther = new FlxCamera();
		camLoading = new FlxCamera();
		luaTpadCam = new FlxCamera();
		camHUD.bgColor.alpha = 0;
		camOther.bgColor.alpha = 0;
		luaTpadCam.bgColor.alpha = 0;

		FlxG.cameras.reset(camGame);
		FlxG.cameras.add(camHUD, false);
		FlxG.cameras.add(camOther, false);
		FlxG.cameras.add(camLoading, false);
		FlxG.cameras.add(luaTpadCam, false);
		FlxG.cameras.setDefaultDrawTarget(camGame, true);

		FlxG.cameras.cameraAdded.addOnce(realignLoadCam);

		CustomFadeTransition.nextCamera = camLoading;
		camGame.bgColor = FlxColor.TRANSPARENT;

		isErect = Difficulty.getString() == "Erect" || Difficulty.getString() == "Nightmare";
		songSuffix = isErect ? "erect" : "";

		canPause = !(GameClient.isConnected() || redditMod);

		var preloadTasks:Array<Void->Void> = [];

		preloadTasks.push(() -> {
			// trace('Playback Rate: ' + playbackRate);

			if (!GameClient.isConnected()) {
				startCallback = startCountdown;
				endCallback = () -> {
					finishingSong = true;
					endSong();
				};
			}
			else {
				paused = true;
				GameClient.send("status", "In-Game");
				startCallback = () -> {
					canStart = false;
					waitReady = true;
					startCountdown();
				};
				endCallback = () -> {
					finishingSong = true;
					GameClient.send("updateSongFP", songPoints);
					GameClient.send("updateMaxCombo", maxCombo);
					GameClient.send("playerEnded");
				};
			}
		});

		preloadTasks.push(() -> {
			// for lua
			instance = this;

			if (GameClient.isConnected())
				replayData = null;

			PauseSubState.songName = null; // Reset to default
			playbackRate = ClientPrefs.getGameplaySetting('songspeed');
			fullComboFunction = fullComboUpdate;

			keysArray = ['note_left', 'note_down', 'note_up', 'note_right'];

			if (FlxG.sound.music != null)
				FlxG.sound.music.stop();

			// Gameplay settings
			healthGain = ClientPrefs.getGameplaySetting('healthgain');
			healthLoss = ClientPrefs.getGameplaySetting('healthloss');
			instakillOnMiss = ClientPrefs.getGameplaySetting('instakill');
			practiceMode = ClientPrefs.getGameplaySetting('practice');
			cpuControlled = ClientPrefs.getGameplaySetting('botplay');
			opponentMode = ClientPrefs.getGameplaySetting('opponentplay');
			noBadNotes = ClientPrefs.getGameplaySetting('nobadnotes');
		});

		preloadTasks.push(() -> {
			grpHoldSplashes = new FlxTypedGroup<SustainSplash>();
			grpNoteSplashes = new FlxTypedGroup<NoteSplash>();

			persistentUpdate = true;
			persistentDraw = true;
		});

		preloadTasks.push(() -> {
			if (SONG == null)
				loadSong('tutorial');

			Conductor.mapBPMChanges(SONG);
			Conductor.bpm = SONG.bpm;

			songId = FreeplayState.filterCharacters(PlayState.SONG.song) + "-" +
				FreeplayState.filterCharacters(Difficulty.getString()) + "-" + 
				FreeplayState.filterCharacters(Md5.encode(PlayState.RAW_SONG))
			;

			#if DISCORD_ALLOWED
			storyDifficultyText = Difficulty.getString();
			#end

			#if DISCORD_ALLOWED
			// String that contains the mode defined here so it isn't necessary to call changePresence for each mode
			if (GameClient.isConnected()) {
				if (!GameClient.room.state.isPrivate)
					detailsText = "Playing against: " + (GameClient.isOwner ? GameClient.room.state.player2.name : GameClient.room.state.player1.name) + "!";
				else
					detailsText = "Playing a online private game!";
			}
			else if (isStoryMode)
				detailsText = "Story Mode: " + WeekData.getCurrentWeek().weekName;
			else {
				if (replayData != null)
					detailsText = replayData.player + "'s Replay";
				else
					detailsText = "Freeplay";
			}

			// String for when the game is paused
			detailsPausedText = "Paused - " + detailsText;
			#end

			GameOverSubstate.resetVariables();
			songName = Paths.formatToSongPath(SONG.song);
		});

		preloadTasks.push(() -> {
			stageModDir = Mods.currentModDirectory; // thats a big woops 
			oldModDir = Mods.currentModDirectory;

			var swagStage = SONG.stage;

			if (GameClient.isConnected() && GameClient.room.state.stageName != '') {
				swagStage = GameClient.room.state.stageName;
				if (GameClient.room.state.stageMod != '')
					Mods.currentModDirectory = stageModDir = GameClient.room.state.stageMod;
			}

			if (swagStage == null || swagStage.length < 1) {
				swagStage = StageData.vanillaSongStage(songName);
			}

			if (isErect && ( //sorry
				swagStage == 'stage' ||
				swagStage == 'spooky' ||
				swagStage == 'philly' ||
				swagStage == 'mall'
			)) {
				swagStage = swagStage + '-erect';
			}
			curStage = swagStage;

			stageData = StageData.getStageFile(curStage);
			if (stageData == null) { // Stage couldn't be found, create a dummy stage for preventing a crash
				stageData = StageData.dummy();
			}

			Mods.currentModDirectory = oldModDir;
			Paths.setCurrentLevel(stageData.directory);

			defaultCamZoom = stageData.defaultZoom;

			stageUI = "normal";
			if (stageData.stageUI != null && stageData.stageUI.trim().length > 0)
				stageUI = stageData.stageUI;
			else {
				if (stageData.isPixelStage)
					stageUI = "pixel";
			}

			BF_X = stageData.boyfriend[0];
			BF_Y = stageData.boyfriend[1];
			GF_X = stageData.girlfriend[0];
			GF_Y = stageData.girlfriend[1];
			DAD_X = stageData.opponent[0];
			DAD_Y = stageData.opponent[1];

			if (stageData.camera_speed != null)
				cameraSpeed = stageData.camera_speed;

			boyfriendCameraOffset = stageData.camera_boyfriend;
			if (boyfriendCameraOffset == null) // Fucks sake should have done it since the start :rolling_eyes:
				boyfriendCameraOffset = [0, 0];

			opponentCameraOffset = stageData.camera_opponent;
			if (opponentCameraOffset == null)
				opponentCameraOffset = [0, 0];

			girlfriendCameraOffset = stageData.camera_girlfriend;
			if (girlfriendCameraOffset == null)
				girlfriendCameraOffset = [0, 0];
		});

		preloadTasks.push(() -> {
			boyfriendGroup = new FlxSpriteGroup(BF_X, BF_Y);
			dadGroup = new FlxSpriteGroup(DAD_X, DAD_Y);
			gfGroup = new FlxSpriteGroup(GF_X, GF_Y);
		});

		preloadTasks.push(() -> {
			switch (curStage) {
				case 'stage': new states.stages.StageWeek1(); // Week 1
				case 'stage-erect': new states.stages.StageErect(); // Week 1 (Erect)
				case 'spooky': new states.stages.Spooky(); // Week 2
				case 'spooky-erect': new states.stages.SpookyErect(); // Week 2 (Erect)
				case 'philly': new states.stages.Philly(); // Week 3
				case 'philly-erect': new states.stages.PhillyErect(); // Week 3 (Erect)
				case 'limo': new states.stages.Limo(); // Week 4
				case 'mall': new states.stages.Mall(); // Week 5 - Cocoa, Eggnog
				case 'mall-erect': new states.stages.MallErect(); // Week 5 (Erect)
				case 'mallEvil': new states.stages.MallEvil(); // Week 5 - Winter Horrorland
				case 'school': new states.stages.School(); // Week 6 - Senpai, Roses
				#if !AWAY_TEST case 'schoolEvil': new states.stages.SchoolEvil(); #end // Week 6 - Thorns
				case 'tank': new states.stages.Tank(); // Week 7 - Ugh, Guns, Stress
			}

			if (stages.length > 0)
				stageExists = true;

			if (isPixelStage) {
				introSoundsSuffix = '-pixel';
				skinsSuffix = '-pixel';
			}
			
			if (curStage.startsWith('mall')) {
				skinsSuffix = '-christmas';
			}

			if (!isPixelStage && ClientPrefs.data.modSkin != null && ClientPrefs.data.modSkin[1].startsWith('pico') && SONG.gfVersion.startsWith('gf')) {
				SONG.gfVersion = 'nene' + skinsSuffix;
			}

			add(gfGroup);
			add(dadGroup);
			add(boyfriendGroup);

			#if LUA_ALLOWED
			luaDebugGroup = new FlxTypedGroup<DebugLuaText>();
			luaDebugGroup.cameras = [camOther];
			add(luaDebugGroup);
			#end
		});

		// "GLOBAL" SCRIPTS
		#if LUA_ALLOWED
		preloadTasks.push(() -> {
			var foldersToCheck:Array<String> = Mods.directoriesWithFile(Paths.getPreloadPath(), 'scripts/');
			for (folder in foldersToCheck)
				for (file in Paths.readDirectory(folder))
				{
					if(file.toLowerCase().endsWith('.lua'))
						new FunkinLua(folder + file);
					#if HSCRIPT_ALLOWED
					if(file.toLowerCase().endsWith('.hx'))
						initHScript(folder + file);
					#end
				}
		});
		#end

		// STAGE SCRIPTS
		#if LUA_ALLOWED
		preloadTasks.push(() -> {
			oldModDir = Mods.currentModDirectory;
			
			Mods.currentModDirectory = stageModDir;
			if (startLuasNamed('stages/' + curStage + '.lua'))
				stageExists = true;

			Mods.currentModDirectory = oldModDir;
		});
		#end

		#if HSCRIPT_ALLOWED
		preloadTasks.push(() -> {
			oldModDir = Mods.currentModDirectory;

			Mods.currentModDirectory = stageModDir;
			if (startHScriptsNamed('stages/' + curStage + '.hx'))
				stageExists = true;

			Mods.currentModDirectory = oldModDir;
		});
		#end

		preloadTasks.push(() -> {
			oldModDir = Mods.currentModDirectory;

			if (!stageData.hide_girlfriend && !(GameClient.isConnected() && GameClient.room.state.hideGF))
			{
				if (SONG.gfVersion == 'nene' || SONG.gfVersion == 'nene-christmas') {
					abot = new ABotSpeaker(-30, 310, curStage == 'spooky-erect');
					updateABotEye(true);
					gfGroup.add(abot);
				}
				
				if(SONG.gfVersion == null || SONG.gfVersion.length < 1) SONG.gfVersion = 'gf'; //Fix for the Chart Editor
				if (!SONG.gfVersion.startsWith('nene'))
					gf = new Character(0, 0, SONG.gfVersion);
				else
					gf = new Nene(0, 0, SONG.gfVersion);
				startCharacterPos(gf);
				gf.scrollFactor.set(0.95, 0.95);
				gfGroup.add(gf);
				startCharacterScripts(gf.curCharacter);
			}
		});

		preloadTasks.push(() -> {
			Mods.currentModDirectory = "";

			if (GameClient.isConnected()) {
				var roomDad = !GameClient.room.state.swagSides ? GameClient.room.state.player1 : GameClient.room.state.player2;
				if (FileSystem.exists(Paths.mods(roomDad.skinMod))) {
					if (roomDad.skinMod != null)
						Mods.currentModDirectory = roomDad.skinMod;

					if (roomDad.skinName != null)
						dad = new Character(0, 0, roomDad.skinName + skinsSuffix, !playsAsBF(), true);
				}
			}
			else if (!playsAsBF() && ClientPrefs.data.modSkin != null) {
				Mods.currentModDirectory = ClientPrefs.data.modSkin[0];
				dad = new Character(0, 0, ClientPrefs.data.modSkin[1] + skinsSuffix, !playsAsBF(), true);
			}

			if (dad == null || dad.loadFailed) {
				Mods.currentModDirectory = oldModDir;
				dad = new Character(0, 0, SONG.player2, !playsAsBF());
			}
			iconP2 = new HealthIcon(dad.healthIcon, false);
			if (!playsAsBF()) {
				dad.flipX = !dad.flipX;
			}
			startCharacterPos(dad, true);
			dadGroup.add(dad);
			startCharacterScripts(dad.curCharacter);

			Mods.currentModDirectory = oldModDir;
		});

		preloadTasks.push(() -> {
			Mods.currentModDirectory = "";

			if (GameClient.isConnected()) {
				var roomBf = !GameClient.room.state.swagSides ? GameClient.room.state.player2 : GameClient.room.state.player1;
				if (FileSystem.exists(Paths.mods(roomBf.skinMod))) {
					if (roomBf.skinMod != null)
						Mods.currentModDirectory = roomBf.skinMod;

					if (roomBf.skinName != null)
						boyfriend = new Character(0, 0, roomBf.skinName + skinsSuffix + "-player", playsAsBF(), true);
				}
			}
			else if (playsAsBF() && ClientPrefs.data.modSkin != null) {
				Mods.currentModDirectory = ClientPrefs.data.modSkin[0];
				boyfriend = new Character(0, 0, ClientPrefs.data.modSkin[1] + skinsSuffix + "-player", playsAsBF(), true);
			}

			if (boyfriend == null || boyfriend.loadFailed) {
				Mods.currentModDirectory = oldModDir;
				boyfriend = new Character(0, 0, SONG.player1, playsAsBF());
			}
			iconP1 = new HealthIcon(boyfriend.healthIcon, true);
			if (!playsAsBF()) {
				boyfriend.flipX = !boyfriend.flipX;
			}
			startCharacterPos(boyfriend);
			boyfriendGroup.add(boyfriend);
			startCharacterScripts(boyfriend.curCharacter);

			Mods.currentModDirectory = oldModDir;
		});

		preloadTasks.push(() -> {
			camPos = FlxPoint.get(girlfriendCameraOffset[0], girlfriendCameraOffset[1]);
			if (gf != null) {
				camPos.x += gf.getGraphicMidpoint().x + gf.cameraPosition[0];
				camPos.y += gf.getGraphicMidpoint().y + gf.cameraPosition[1];
			}

			if (dad.curCharacter.startsWith('gf') && Paths.formatToSongPath(SONG.song) == 'tutorial') {
				dad.setPosition(GF_X, GF_Y);
				if (gf != null)
					gf.visible = false;
			}
			stagesFunc(function(stage:BaseStage) stage.createPost());
		});

		preloadTasks.push(() -> {
			comboGroup = new FlxSpriteGroup();
			add(comboGroup);
			noteGroup = new FlxTypedGroup<FlxBasic>();
			add(noteGroup);
			uiGroup = new FlxSpriteGroup();
			add(uiGroup);

			uiGroup.cameras = [camHUD];
			noteGroup.cameras = [camHUD];
			comboGroup.cameras = [camHUD];
		});

		preloadTasks.push(() -> {
			Conductor.songPosition = -5000 / Conductor.songPosition;
			showTime = (ClientPrefs.data.timeBarType != 'Disabled');
			timeTxt = new FlxText(STRUM_X + (FlxG.width / 2) - 248, 19, 400, "", 32);
			timeTxt.setFormat(!isPixelStage ? Paths.font("vcr.ttf") : 'Pixel Arial 11 Bold', !isPixelStage ? 32 : 28, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			timeTxt.scrollFactor.set();
			timeTxt.alpha = 0;
			timeTxt.borderSize = 2;
			timeTxt.visible = updateTime = showTime;
			if(ClientPrefs.data.downScroll) timeTxt.y = FlxG.height - 44;
			if(ClientPrefs.data.timeBarType == 'Song Name') timeTxt.text = SONG.song;
		});

		preloadTasks.push(() -> {
			timeBar = new HealthBar(0, timeTxt.y + (timeTxt.height / 4), 'timeBar', function() return songPercent, 0, 1);
			timeBar.scrollFactor.set();
			timeBar.screenCenter(X);
			timeBar.alpha = 0;
			timeBar.visible = showTime;
			uiGroup.add(timeBar);
			uiGroup.add(timeTxt);
		});

		preloadTasks.push(() -> {
			strumLineNotes = new FlxTypedGroup<StrumNote>();
			noteGroup.add(strumLineNotes);
			noteGroup.add(grpHoldSplashes);
			noteGroup.add(grpNoteSplashes);

			var splash:NoteSplash = new NoteSplash(100, 100);
			grpNoteSplashes.add(splash);
			splash.alpha = 0.0001; //cant make it invisible or it won't allow precaching

			SustainSplash.startCrochet = Conductor.stepCrochet;
			SustainSplash.frameRate = Math.floor(24 / 100 * SONG.bpm);
			var splash:SustainSplash = new SustainSplash();
			grpHoldSplashes.add(splash);
			splash.visible = true;
			splash.alpha = 0.0001;

			opponentStrums = new FlxTypedGroup<StrumNote>();
			playerStrums = new FlxTypedGroup<StrumNote>();
		});

		#if AWAY_TEST
		preloadTasks.push(() -> {
			Main.stage3D.setupOnlineStage();
		});
		#end

		preloadTasks.push(() -> {
			generateSong(SONG.song);
		});

		preloadTasks.push(() -> {
			camFollow = new FlxObject(0, 0, 1, 1);
			camFollow.setPosition(camPos.x, camPos.y);
			camPos.put();
					
			if (prevCamFollow != null)
			{
				camFollow = prevCamFollow;
				prevCamFollow = null;
			}
			add(camFollow);

			FlxG.camera.follow(camFollow, LOCKON, 0);
			FlxG.camera.zoom = defaultCamZoom;
			FlxG.camera.snapToTarget();

			FlxG.worldBounds.set(0, 0, FlxG.width, FlxG.height);
			moveCameraSection();
		});

		preloadTasks.push(() -> {
			healthBar = new HealthBar(0, FlxG.height * (!ClientPrefs.data.downScroll ? 0.89 : 0.11), 'healthBar', function() return health, 0, 2);
			healthBar.screenCenter(X);
			healthBar.leftToRight = false;
			healthBar.scrollFactor.set();
			healthBar.visible = !ClientPrefs.data.hideHud;
			healthBar.alpha = ClientPrefs.data.healthBarAlpha;
			reloadHealthBarColors();
			uiGroup.add(healthBar);

			iconP1.y = healthBar.y - 75;
			iconP1.visible = !ClientPrefs.data.hideHud;
			iconP1.alpha = ClientPrefs.data.healthBarAlpha;
			uiGroup.add(iconP1);

			iconP2.y = healthBar.y - 75;
			iconP2.visible = !ClientPrefs.data.hideHud;
			iconP2.alpha = ClientPrefs.data.healthBarAlpha;
			uiGroup.add(iconP2);
		});

		preloadTasks.push(() -> {
			scoreTxt = new FlxText(0, healthBar.y + 40, FlxG.width, "", 20);
			scoreTxt.setFormat(!isPixelStage ? Paths.font("vcr.ttf") : 'Pixel Arial 11 Bold', !isPixelStage ? 20 : 18, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			scoreTxt.scrollFactor.set();
			scoreTxt.borderSize = 1.25;
			scoreTxt.visible = !ClientPrefs.data.hideHud;
			uiGroup.add(scoreTxt);
		});

		if (GameClient.isConnected()) {
			preloadTasks.push(() -> {
				scoreTxt.visible = false;

				scoreTxtP1 = new FlxText(0, healthBar.y + 40, FlxG.width, "?", 20);
				scoreTxtP1.setFormat(!isPixelStage ? Paths.font("vcr.ttf") : 'Pixel Arial 11 Bold', !isPixelStage ? 18 : 16, FlxColor.WHITE, LEFT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				scoreTxtP1.scrollFactor.set();
				scoreTxtP1.borderSize = 1.25;
				scoreTxtP1.visible = !ClientPrefs.data.hideHud;
				scoreTxtP1.camera = camOther;
				uiGroup.add(scoreTxtP1);
			});

			preloadTasks.push(() -> {
				scoreTxtP2 = new FlxText(0, healthBar.y + 40, FlxG.width, "?", 20);
				scoreTxtP2.setFormat(!isPixelStage ? Paths.font("vcr.ttf") : 'Pixel Arial 11 Bold', !isPixelStage ? 18 : 16, FlxColor.WHITE, RIGHT, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
				scoreTxtP2.scrollFactor.set();
				scoreTxtP2.borderSize = 1.25;
				scoreTxtP2.visible = !ClientPrefs.data.hideHud;
				scoreTxtP2.camera = camOther;
				uiGroup.add(scoreTxtP2);

				scoreTxtP1.y -= scoreTxtP1.height * 3;
				scoreTxtP2.y -= scoreTxtP2.height * 3;

				scoreTxtP1.offset.x -= 30;
				scoreTxtP2.offset.x += 30;
			});
		}

		preloadTasks.push(() -> {
			botplayTxt = new FlxText(0, timeBar.y + 55, 0, "BOTPLAY", 32);
			botplayTxt.setFormat(Paths.font("vcr.ttf"), 32, FlxColor.WHITE, CENTER, FlxTextBorderStyle.OUTLINE, FlxColor.BLACK);
			botplayTxt.scrollFactor.set();
			botplayTxt.borderSize = 1.25;
			showBotplay();
			uiGroup.add(botplayTxt);
			if (ClientPrefs.data.downScroll) {
				botplayTxt.y = timeBar.y - 78;
			}

			startingSong = true;
		});
		
		#if LUA_ALLOWED
		preloadTasks.push(() -> {
			for (notetype in noteTypes)
				startLuasNamed('custom_notetypes/' + notetype + '.lua');
		});

		preloadTasks.push(() -> {
			for (event in eventsPushed)
				startLuasNamed('custom_events/' + event + '.lua');
		});
		#end

		#if HSCRIPT_ALLOWED
		preloadTasks.push(() -> {
			for (notetype in noteTypes)
				startHScriptsNamed('custom_notetypes/' + notetype + '.hx');
		});

		preloadTasks.push(() -> {
			for (event in eventsPushed)
				startHScriptsNamed('custom_events/' + event + '.hx');
		});
		#end

		preloadTasks.push(() -> {
			noteTypes = null;
			eventsPushed = null;

			if(eventNotes.length > 1)
			{
				for (event in eventNotes) event.strumTime -= eventEarlyTrigger(event);
				eventNotes.sort(sortByTime);
			}
		});

		// SONG SPECIFIC SCRIPTS
		#if LUA_ALLOWED
		preloadTasks.push(() -> {
			var foldersToCheck:Array<String> = Mods.directoriesWithFile(Paths.getPreloadPath(), 'data/' + songName + '/');
			for (folder in foldersToCheck)
				for (file in Paths.readDirectory(folder)) {
					if (file.toLowerCase().endsWith('.lua'))
						new FunkinLua(folder + file);
					#if HSCRIPT_ALLOWED
					if (file.toLowerCase().endsWith('.hx'))
						initHScript(folder + file);
					#end
				}
		});
		#end

		if (GameClient.isConnected()) {
			preloadTasks.push(() -> {
				waitReadySpr = new Alphabet(0, 0, controls.mobileC ? "TOUCH YOUR SCREEN TO START" : "PRESS ACCEPT TO START", true);
				waitReadySpr.cameras = [camOther];
				waitReadySpr.alpha = 0;
				waitReadySpr.alignment = CENTERED;
				waitReadySpr.x = FlxG.width / 2;
				waitReadySpr.screenCenter(Y);
			});
		}

		preloadTasks.push(() -> {
			RecalculateRating();
			if (GameClient.isConnected())
				RecalculateRatingOpponent();
		});

		preloadTasks.push(() -> {
			//PRECACHING MISS SOUNDS BECAUSE I THINK THEY CAN LAG PEOPLE AND FUCK THEM UP IDK HOW HAXE WORKS
			if(ClientPrefs.data.hitsoundVolume > 0) precacheList.set('hitsound', 'sound');
			precacheList.set('missnote1', 'sound');
			precacheList.set('missnote2', 'sound');
			precacheList.set('missnote3', 'sound');

			if (PauseSubState.songName != null) {
				precacheList.set(PauseSubState.songName, 'music');
			} else if(ClientPrefs.data.pauseMusic != 'None') {
				precacheList.set(Paths.formatToSongPath(ClientPrefs.data.pauseMusic), 'music');
			}

			precacheList.set('alphabet', 'image');
			resetRPC();
		});

		preloadTasks.push(() -> {
			#if LUA_ALLOWED
			for (_ in modchartSprites) {
				stageExists = true;
				break;
			}
			#end

			if (!stageExists) {
				Sys.println("STAGE IS EMPTY");
				var prevLevel = Paths.currentLevel;
				Paths.setCurrentLevel("week1");
				//new online.OnlineStage();
				Paths.setCurrentLevel(prevLevel);
			}
		});

		preloadTasks.push(() -> {
			cacheCountdown();
			cachePopUpScore();
			
			for (key => type in precacheList)
			{
				//trace('Key $key is type $type');
				switch(type)
				{
					case 'image':
						Paths.image(key);
					case 'sound':
						Paths.sound(key);
					case 'music':
						Paths.music(key);
				}
			}
		});

		if (GameClient.isConnected()) {
			preloadTasks.push(() -> {
				add(chatBox = new ChatBox(camOther, 100));
				add(leavePie = new LeavePie());
				leavePie.cameras = [camOther];
				add(waitReadySpr);
				waitReadySpr.visible = false;
			});
		}

		preloadTasks.push(() -> {
			if (replayData != null && !GameClient.isConnected()) {
				add(replayPlayer = new ReplayPlayer(this, replayData));
			}
			else {
				FlxG.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
				FlxG.stage.addEventListener(KeyboardEvent.KEY_UP, onKeyRelease);

				if (!ClientPrefs.data.disableReplays && !isInvalidScore() && !chartingMode) {
					add(replayRecorder = new ReplayRecorder(this));
				}
			}

			if (!ClientPrefs.data.disableSongComments && replayPlayer != null && songId != null) {
				nicomments = new NicommentsView(songId);
				nicomments.cameras = [camOther];
				add(nicomments);
			}

			Paths.clearUnusedMemory();

			CustomFadeTransition.nextCamera = camOther;
			if (eventNotes.length < 1)
				checkEventNote();

			if (GameClient.isConnected())
				generateStrums();
		});

		var loaderGroup = new online.objects.LoadingSprite(preloadTasks.length, camLoading);
		add(loaderGroup);
		
		asyncLoop = new FlxAsyncLoop(preloadTasks.length, () -> {
			preloadTasks.shift()();

			loaderGroup.addProgress(preloadTasks.length);

			if (preloadTasks.length <= 0) {
				isCreated = true;

				FlxTween.tween(camLoading, {alpha: 0}, 0.5, {ease: FlxEase.circOut, onComplete: t -> {
					loaderGroup.killMembers();
					FlxG.cameras.remove(camLoading, true);
				}});

				if (redditMod) {
					online.util.FileUtils.removeFiles(haxe.io.Path.join([Paths.mods(), 'reddit']));
				}

				startCallback();
				callOnScripts('onCreatePost');
				registerMessages();

				add(new online.objects.DebugPosHelper());
			}
		}, 1);
		loaderGroup.add(asyncLoop);

		orderOffset = 2;

		addMobileControls();
		addTouchPad((replayData != null) ? 'LEFT_RIGHT' : 'NONE', (GameClient.isConnected()) ? 'P_C_T' : (replayData != null) ? #if android 'X_Y' : 'T' #else 'P_X_Y' : 'P_T' #end);
		addTouchPadCamera();
		mobileControls.onButtonDown.add(onButtonPress);
		mobileControls.onButtonUp.add(onButtonRelease);
		if (replayData == null)
			mobileControls.instance.visible = true;
		mobileControls.instance.forEachAlive((button) ->
		{
			if (touchPad.buttonT != null)
    				button.deadZones.push(touchPad.buttonT);
			if (touchPad.buttonC != null)
    				button.deadZones.push(touchPad.buttonC);
			if (touchPad.buttonP != null)			
					button.deadZones.push(touchPad.buttonP);
		});

		super.create();
	}

	function updateABotEye(finishInstantly:Bool = false) {
		if(aLookAt == 1)
			abot.lookRight();
		else
			abot.lookLeft();

		if(finishInstantly) abot.eyes.anim.curFrame = abot.eyes.anim.length - 1;
	}

	@:unreflective public var botplayVisibility = false;
	function showBotplay() {
		if (botplayTxt == null)
			return;

		var pos = 0;
		
		botplayVisibility = cpuControlled;

		if (GameClient.isConnected()) {
			if (GameClient.room.state.player1.botplay && GameClient.room.state.player2.botplay)
				pos = 0;
			else if (GameClient.room.state.player1.botplay)
				pos = (GameClient.room.state.swagSides ? 2 : 1);
			else if (GameClient.room.state.player2.botplay)
				pos = (GameClient.room.state.swagSides ? 1 : 2);
			else
				pos = -1;

			botplayVisibility = pos != -1;
		}

		botplayTxt.x = FlxG.width / 2 - botplayTxt.width / 2;

		switch (pos) {
			case 1:
				botplayTxt.x -= 320;
			case 2:
				botplayTxt.x += 320;
		}

		botplayTxt.visible = botplayVisibility;
	}

	function realignLoadCam(cam:FlxCamera) {
		if (cam == camLoading || !FlxG.cameras.list.contains(camLoading))
			return;

		FlxG.cameras.remove(camLoading, false);
		FlxG.cameras.add(camLoading, false);
		FlxG.cameras.cameraAdded.addOnce(realignLoadCam);
	}

	function set_songSpeed(value:Float):Float
	{
		if(generatedMusic)
		{
			var ratio:Float = value / songSpeed; //funny word huh
			if(ratio != 1)
			{
				for (note in notes.members) note.resizeByRatio(ratio);
				for (note in unspawnNotes) note.resizeByRatio(ratio);
			}
		}
		songSpeed = value;
		noteKillOffset = Math.max(Conductor.stepCrochet, 350 / songSpeed * playbackRate);
		return value;
	}

	function set_playbackRate(value:Float):Float
	{
		#if FLX_PITCH
		if(generatedMusic)
		{
			vocals.pitch = value;
			opponentVocals.pitch = value;
			FlxG.sound.music.pitch = value;

			var ratio:Float = playbackRate / value; //funny word huh
			if(ratio != 1)
			{
				for (note in notes.members) note.resizeByRatio(ratio);
				for (note in unspawnNotes) note.resizeByRatio(ratio);
			}
		}
		#else 
		value = 1;
		#end

		playbackRate = value;
		FlxG.animationTimeScale = value;
		Conductor.safeZoneOffset = (ClientPrefs.getSafeFrames() / 60) * 1000 * value;
		#if VIDEOS_ALLOWED
		if(videoCutscene != null && videoCutscene.videoSprite != null) videoCutscene.videoSprite.bitmap.rate = value;
		#end
		setOnScripts('playbackRate', playbackRate);
		return value;
	}

	public function addTextToDebug(text:String, color:FlxColor) {
		if (!ClientPrefs.isDebug()) {
			return;
		}

		#if LUA_ALLOWED
		var newText:DebugLuaText = luaDebugGroup.recycle(DebugLuaText);
		newText.text = text;
		newText.color = color;
		newText.disableTime = 6;
		newText.alpha = 1;
		newText.setPosition(10, 8 - newText.height);

		luaDebugGroup.forEachAlive(function(spr:DebugLuaText) {
			spr.y += newText.height + 2;
		});
		luaDebugGroup.add(newText);
		#end
	}

	public function reloadHealthBarColors() {
		healthBar.setColors(FlxColor.fromRGB(dad.healthColorArray[0], dad.healthColorArray[1], dad.healthColorArray[2]),
			FlxColor.fromRGB(boyfriend.healthColorArray[0], boyfriend.healthColorArray[1], boyfriend.healthColorArray[2]));
	}

	public function addCharacterToList(newCharacter:String, type:Int) {
		switch(type) {
			case 0:
				if (!ClientPrefs.data.modchartSkinChanges && boyfriend.isSkin)
					return;

				if(!boyfriendMap.exists(newCharacter)) {
					var newBoyfriend:Character;
					if (boyfriend.isSkin && newCharacter == SONG.player1)
						newBoyfriend = boyfriend;
					else {
						newBoyfriend = new Character(0, 0, newCharacter, true);
						boyfriendGroup.add(newBoyfriend);
						startCharacterPos(newBoyfriend);
						newBoyfriend.alpha = 0.00001;
						startCharacterScripts(newBoyfriend.curCharacter);
					}
						
					boyfriendMap.set(newCharacter, newBoyfriend);
				}

			case 1:
				if (!ClientPrefs.data.modchartSkinChanges && dad.isSkin)
					return;

				if(!dadMap.exists(newCharacter)) {
					var newDad:Character;
					if (dad.isSkin && newCharacter == SONG.player2)
						newDad = dad;
					else {
						newDad = new Character(0, 0, newCharacter);
						dadGroup.add(newDad);
						startCharacterPos(newDad, true);
						newDad.alpha = 0.00001;
						startCharacterScripts(newDad.curCharacter);
					}
					dadMap.set(newCharacter, newDad);
				}

			case 2:
				if(gf != null && !gfMap.exists(newCharacter)) {
					var newGf:Character = new Character(0, 0, newCharacter);
					newGf.scrollFactor.set(0.95, 0.95);
					gfMap.set(newCharacter, newGf);
					gfGroup.add(newGf);
					startCharacterPos(newGf);
					newGf.alpha = 0.00001;
					startCharacterScripts(newGf.curCharacter);
				}
		}
	}

	function startCharacterScripts(name:String)
	{
		// Lua
		#if LUA_ALLOWED
		var doPush:Bool = false;
		var luaFile:String = 'characters/' + name + '.lua';
		#if MODS_ALLOWED
		var replacePath:String = Paths.modFolders(luaFile);
		if(FileSystem.exists(replacePath))
		{
			luaFile = replacePath;
			doPush = true;
		}
		else
		{
			luaFile = Paths.getPreloadPath(luaFile);
			if(FileSystem.exists(luaFile))
				doPush = true;
		}
		#else
		luaFile = Paths.getPreloadPath(luaFile);
		if(Assets.exists(luaFile)) doPush = true;
		#end

		if(doPush)
		{
			for (script in luaArray)
			{
				if(script.scriptName == luaFile)
				{
					doPush = false;
					break;
				}
			}
			if(doPush) new FunkinLua(luaFile);
		}
		#end

		// HScript
		#if HSCRIPT_ALLOWED
		var doPush:Bool = false;
		var scriptFile:String = 'characters/' + name + '.hx';
		var replacePath:String = Paths.modFolders(scriptFile);
		if(FileSystem.exists(replacePath))
		{
			scriptFile = replacePath;
			doPush = true;
		}
		else
		{
			scriptFile = Paths.getPreloadPath(scriptFile);
			if(FileSystem.exists(scriptFile))
				doPush = true;
		}
		
		if(doPush)
		{
			if(SScript.global.exists(scriptFile))
				doPush = false;

			if(doPush) initHScript(scriptFile);
		}
		#end
	}

	public function getLuaObject(tag:String, text:Bool=true):FlxSprite {
		#if LUA_ALLOWED
		if(modchartSprites.exists(tag)) return modchartSprites.get(tag);
		if(text && modchartTexts.exists(tag)) return modchartTexts.get(tag);
		if(variables.exists(tag)) return variables.get(tag);
		#end
		return null;
	}

	function startCharacterPos(char:Character, ?gfCheck:Bool = false) {
		if(gfCheck && char.curCharacter.startsWith('gf') && Paths.formatToSongPath(SONG.song) == 'tutorial') { //IF DAD IS GIRLFRIEND, HE GOES TO HER POSITION
			char.setPosition(GF_X, GF_Y);
			char.scrollFactor.set(0.95, 0.95);
			char.danceEveryNumBeats = 2;
		}
		char.x += char.positionArray[0];
		char.y += char.positionArray[1];
	}

	#if hxCodec
	public function startVideoCodec(name:String)
	{
		#if VIDEOS_ALLOWED
		inCutscene = true;

		var filepath:String = Paths.video(name);
		#if sys
		if(!FileSystem.exists(filepath))
		#else
		if(!OpenFlAssets.exists(filepath))
		#end
		{
			FlxG.log.warn('Couldnt find video file: ' + name);
			startAndEnd();
			return;
		}

		var video:VideoHandler = new VideoHandler();
			#if (hxCodec >= "3.0.0")
			// Recent versions
			video.play(filepath);
			video.onEndReached.add(function()
			{
				video.dispose();
				startAndEnd();
				return;
			}, true);
			#else
			// Older versions
			video.playVideo(filepath);
			video.finishCallback = function()
			{
				startAndEnd();
				return;
			}
			#end
		#else
		FlxG.log.warn('Platform not supported!');
		startAndEnd();
		return;
		#end
	}
	#end

	public var videoCutscene:VideoSprite = null;
	public function startVideo(name:String, forMidSong:Bool = false, canSkip:Bool = true, loop:Bool = false, playOnLoad:Bool = true)
	{
		#if VIDEOS_ALLOWED
		inCutscene = !forMidSong;
		canPause = forMidSong;

		var foundFile:Bool = false;
		var fileName:String = Paths.video(name);

		#if sys
		if (FileSystem.exists(fileName))
		#else
		if (OpenFlAssets.exists(fileName))
		#end
		foundFile = true;

		if (foundFile)
		{
			videoCutscene = new VideoSprite(fileName, forMidSong, canSkip, loop);
			if(forMidSong) videoCutscene.videoSprite.bitmap.rate = playbackRate;

			// Finish callback
			if (!forMidSong)
			{
				function onVideoEnd()
				{
					if (!isDead && generatedMusic && PlayState.SONG.notes[Std.int(curStep / 16)] != null && !endingSong && !isCameraOnForcedPos)
					{
						moveCameraSection();
						FlxG.camera.snapToTarget();
					}
					videoCutscene = null;
					canPause = true;
					inCutscene = false;
					startAndEnd();
				}
				videoCutscene.finishCallback = onVideoEnd;
				videoCutscene.onSkip = onVideoEnd;
			}
			if (GameOverSubstate.instance != null && isDead) GameOverSubstate.instance.add(videoCutscene);
			else add(videoCutscene);

			if (playOnLoad)
				videoCutscene.play();
			return videoCutscene;
		}
		#if (LUA_ALLOWED || HSCRIPT_ALLOWED)
		else addTextToDebug("Video not found: " + fileName, FlxColor.RED);
		#else
		else FlxG.log.error("Video not found: " + fileName);
		#end
		#else
		FlxG.log.warn('Platform not supported!');
		startAndEnd();
		#end
		return null;
	}

	function startAndEnd()
	{
		if (FlxG.state != this)
			return;

		if(endingSong)
			endSong();
		else
			startCountdown();
	}

	var dialogueCount:Int = 0;
	public var psychDialogue:DialogueBoxPsych;
	//You don't have to add a song, just saying. You can just do "startDialogue(DialogueBoxPsych.parseDialogue(Paths.json(songName + '/dialogue')))" and it should load dialogue.json
	public function startDialogue(dialogueFile:DialogueFile, ?song:String = null):Void
	{
		// TO DO: Make this more flexible, maybe?
		if(psychDialogue != null) return;

		if(dialogueFile.dialogue.length > 0) {
			inCutscene = true;
			precacheList.set('dialogue', 'sound');
			precacheList.set('dialogueClose', 'sound');
			psychDialogue = new DialogueBoxPsych(dialogueFile, song);
			psychDialogue.scrollFactor.set();
			if(endingSong) {
				psychDialogue.finishThing = function() {
					psychDialogue = null;
					endSong();
				}
			} else {
				psychDialogue.finishThing = function() {
					psychDialogue = null;
					startCountdown();
				}
			}
			psychDialogue.nextDialogueThing = startNextDialogue;
			psychDialogue.skipDialogueThing = skipDialogue;
			psychDialogue.cameras = [camHUD];
			add(psychDialogue);
		} else {
			FlxG.log.warn('Your dialogue file is badly formatted!');
			startAndEnd();
		}
	}

	var startTimer:FlxTimer;
	var finishTimer:FlxTimer = null;

	// For being able to mess with the sprites on Lua
	public var countdownReady:FlxSprite;
	public var countdownSet:FlxSprite;
	public var countdownGo:FlxSprite;
	public static var startOnTime:Float = 0;

	function cacheCountdown()
	{
		var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
		var introImagesArray:Array<String> = switch(stageUI) {
			case "pixel": ['${stageUI}UI/ready-pixel', '${stageUI}UI/set-pixel', '${stageUI}UI/date-pixel'];
			case "normal": ["ready", "set" ,"go"];
			default: ['${stageUI}UI/ready', '${stageUI}UI/set', '${stageUI}UI/go'];
		}
		introAssets.set(stageUI, introImagesArray);
		var introAlts:Array<String> = introAssets.get(stageUI);
		for (asset in introAlts) Paths.image(asset);
		
		Paths.sound('intro3' + introSoundsSuffix);
		Paths.sound('intro2' + introSoundsSuffix);
		Paths.sound('intro1' + introSoundsSuffix);
		Paths.sound('introGo' + introSoundsSuffix);
	}

	public function generateStrums() {
		if (skipCountdown || startOnTime > 0)
			skipArrowStartTween = true;

		generateStaticArrows(0);
		generateStaticArrows(1);
		for (i in 0...playerStrums.length) {
			setOnScripts('defaultPlayerStrumX' + i, playerStrums.members[i].x);
			setOnScripts('defaultPlayerStrumY' + i, playerStrums.members[i].y);
		}
		for (i in 0...opponentStrums.length) {
			setOnScripts('defaultOpponentStrumX' + i, opponentStrums.members[i].x);
			setOnScripts('defaultOpponentStrumY' + i, opponentStrums.members[i].y);
			// if(ClientPrefs.data.middleScroll) opponentStrums.members[i].visible = false;
		}
	}

	public function startCountdown()
	{
		theWorld = false;

		if(startedCountdown) {
			callOnScripts('onStartCountdown');
			return false;
		}

		seenCutscene = true;
		inCutscene = false;
		var ret:Dynamic = callOnScripts('onStartCountdown', null, true);
		if(ret != FunkinLua.Function_Stop) {
			if (!canStart) {
				canStart = true;
				waitReadySpr.visible = true;
				return false;
			}
			if (!GameClient.isConnected())
				generateStrums();

			startedCountdown = true;
			Conductor.songPosition = -Conductor.crochet * 5;
			setOnScripts('startedCountdown', true);
			callOnScripts('onCountdownStarted', null);

			var swagCounter:Int = 0;
			if (startOnTime > 0) {
				clearNotesBefore(startOnTime);
				setSongTime(startOnTime - 350);
				return true;
			}
			else if (skipCountdown)
			{
				setSongTime(0);
				return true;
			}
			moveCameraSection();

			startTimer = new FlxTimer().start(Conductor.crochet / 1000 / playbackRate, function(tmr:FlxTimer)
			{
				if (gf != null && tmr.loopsLeft % Math.round(gfSpeed * gf.danceEveryNumBeats) == 0 && gf.animation.curAnim != null && !gf.animation.curAnim.name.startsWith("sing") && !gf.stunned)
					gf.dance();
				if (tmr.loopsLeft % boyfriend.danceEveryNumBeats == 0 && boyfriend.animation.curAnim != null && !boyfriend.animation.curAnim.name.startsWith('sing') && !boyfriend.stunned)
					boyfriend.dance();
				if (tmr.loopsLeft % dad.danceEveryNumBeats == 0 && dad.animation.curAnim != null && !dad.animation.curAnim.name.startsWith('sing') && !dad.stunned)
					dad.dance();

				var introAssets:Map<String, Array<String>> = new Map<String, Array<String>>();
				var introImagesArray:Array<String> = switch(stageUI) {
					case "pixel": ['${stageUI}UI/ready-pixel', '${stageUI}UI/set-pixel', '${stageUI}UI/date-pixel'];
					case "normal": ["ready", "set" ,"go"];
					default: ['${stageUI}UI/ready', '${stageUI}UI/set', '${stageUI}UI/go'];
				}
				introAssets.set(stageUI, introImagesArray);

				var introAlts:Array<String> = introAssets.get(stageUI);
				var antialias:Bool = (ClientPrefs.data.antialiasing && !isPixelStage);
				var tick:Countdown = THREE;

				switch (swagCounter)
				{
					case 0:
						FlxG.sound.play(Paths.sound('intro3' + introSoundsSuffix), 0.6);
						tick = THREE;
					case 1:
						countdownReady = createCountdownSprite(introAlts[0], antialias);
						FlxG.sound.play(Paths.sound('intro2' + introSoundsSuffix), 0.6);
						tick = TWO;
					case 2:
						countdownSet = createCountdownSprite(introAlts[1], antialias);
						FlxG.sound.play(Paths.sound('intro1' + introSoundsSuffix), 0.6);
						tick = ONE;
					case 3:
						countdownGo = createCountdownSprite(introAlts[2], antialias);
						FlxG.sound.play(Paths.sound('introGo' + introSoundsSuffix), 0.6);
						tick = GO;
					case 4:
						tick = START;
				}

				notes.forEachAlive(function(note:Note) {
					if(ClientPrefs.data.opponentStrums || isPlayerNote(note))
					{
						note.copyAlpha = false;
						note.noteAlpha = note.multAlpha;
						if (ClientPrefs.data.middleScroll && !isPlayerNote(note))
							note.noteAlpha *= 0.35;
					}
				});

				stagesFunc(function(stage:BaseStage) stage.countdownTick(tick, swagCounter));
				callOnLuas('onCountdownTick', [swagCounter]);
				callOnHScript('onCountdownTick', [tick, swagCounter]);

				swagCounter += 1;
			}, 5);
		}
		return true;
	}

	inline private function createCountdownSprite(image:String, antialias:Bool):FlxSprite
	{
		var spr:FlxSprite = new FlxSprite().loadGraphic(Paths.image(image));
		spr.cameras = [camHUD];
		spr.scrollFactor.set();
		spr.updateHitbox();

		if (PlayState.isPixelStage)
			spr.setGraphicSize(Std.int(spr.width * daPixelZoom));

		spr.screenCenter();
		spr.antialiasing = antialias;
		insert(members.indexOf(noteGroup), spr);
		FlxTween.tween(spr, {/*y: spr.y + 100,*/ alpha: 0}, Conductor.crochet / 1000, {
			ease: FlxEase.cubeInOut,
			onComplete: function(twn:FlxTween)
			{
				remove(spr);
				spr.destroy();
			}
		});
		return spr;
	}

	public function addBehindGF(obj:FlxBasic)
	{
		insert(members.indexOf(gfGroup), obj);
	}
	public function addBehindBF(obj:FlxBasic)
	{
		insert(members.indexOf(boyfriendGroup), obj);
	}
	public function addBehindDad(obj:FlxBasic)
	{
		insert(members.indexOf(dadGroup), obj);
	}

	public function clearNotesBefore(time:Float)
	{
		if (replayPlayer != null) {
			replayPlayer.timeJump(time);
		}

		if (nicomments != null) {
			nicomments.timeJump(time);
		}

		var i:Int = unspawnNotes.length - 1;
		while (i >= 0) {
			var daNote:Note = unspawnNotes[i];
			if(daNote.strumTime - 350 < time)
			{
				daNote.active = false;
				daNote.visible = false;
				daNote.ignoreNote = true;

				//if(!ClientPrefs.data.lowQuality || !cpuControlled) daNote.kill();
				unspawnNotes.remove(daNote);
				daNote.destroy();
			}
			--i;
		}

		i = notes.length - 1;
		while (i >= 0) {
			var daNote:Note = notes.members[i];
			if(daNote.strumTime - 350 < time)
			{
				daNote.active = false;
				daNote.visible = false;
				daNote.ignoreNote = true;

				//if(!ClientPrefs.data.lowQuality || !cpuControlled) daNote.kill();
				notes.remove(daNote, true);
				daNote.destroy();
			}
			--i;
		}
	}

	public function updateScore(miss:Bool = false, ?skipRest:Bool = false)
	{
		var scoreTextObject = scoreTxt;
		if (GameClient.isConnected()) {
			scoreTextObject = (!playsAsBF() ? scoreTxtP1 : scoreTxtP2);
		}

		var str:String = ratingName;
		if (totalPlayed != 0) {
			var percent:Float = CoolUtil.floorDecimal(ratingPercent * 100, 2);
			str += ' ($percent%) - $ratingFC';
		}

		if (GameClient.isConnected()) {
			scoreTextObject.text = (GameClient.isOwner ? GameClient.room.state.player1 : GameClient.room.state.player2).name
				+ '\nScore: ' + FlxStringUtil.formatMoney(songScore, false)
				+ '\nMisses: ' + songMisses
				+ '\nRating: ' + str
				+ "\nPing: " + (GameClient.isOwner ? GameClient.room.state.player1 : GameClient.room.state.player2).ping;
		}
		else {
			scoreTextObject.text = 'Score: ' + FlxStringUtil.formatMoney(songScore, false) + ' | Misses: ' + songMisses + ' | Rating: ' + str;
		}

		var points = online.FunkinPoints.calcFP(ratingPercent, songMisses, songDensity, totalNotesHit, maxCombo);
		if (points != songPoints) {
			songPoints = points;
			if (totalPlayed != 0) {
				var maxPoints = online.FunkinPoints.calcFP(1, 0, songDensity, totalPlayed, totalPlayed);
				pointsPercent = Math.min(1, Math.max(0, points / maxPoints));
			}
			resetRPC(true);
		}
		songPoints = points;

		if (skipRest) {
			if (ClientPrefs.data.showFP)
				scoreTextObject.text += ' | FP: ' + songPoints + ' (${CoolUtil.floorDecimal(pointsPercent * 100, 1)}%)';
			return;
		}

		if (ClientPrefs.data.scoreZoom && !miss && !cpuControlled) {
			if (scoreTxtTween != null) {
				scoreTxtTween.cancel();
			}
			if (!GameClient.isConnected()) {
				scoreTextObject.scale.x = 1.075;
				scoreTextObject.scale.y = 1.075;
			}
			else {
				scoreTextObject.scale.x = 1.045;
				scoreTextObject.scale.y = 1.045;
			}
			scoreTxtTween = FlxTween.tween(scoreTextObject.scale, {x: 1, y: 1}, 0.2, {
				onComplete: function(twn:FlxTween) {
					scoreTxtTween = null;
				}
			});
		}
		callOnScripts('onUpdateScore', [miss]);
		if (ClientPrefs.data.showFP)
			scoreTextObject.text += ' | FP: ' + songPoints + ' (${CoolUtil.floorDecimal(pointsPercent * 100, 1)}%)';
	}

	public function setSongTime(time:Float)
	{
		if(time < 0) time = 0;

		FlxG.sound.music.pause();
		vocals.pause();
		opponentVocals.pause();

		FlxG.sound.music.time = time;
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		FlxG.sound.music.play();

		if (Conductor.songPosition <= vocals.length)
		{
			vocals.time = time;
			#if FLX_PITCH vocals.pitch = playbackRate; #end
		}
		if (Conductor.songPosition <= opponentVocals.length) {
			opponentVocals.time = time;
			#if FLX_PITCH opponentVocals.pitch = playbackRate; #end
		}
		vocals.play();
		opponentVocals.play();
		Conductor.songPosition = time;
	}

	public function startNextDialogue() {
		dialogueCount++;
		callOnScripts('onNextDialogue', [dialogueCount]);
	}

	public function skipDialogue() {
		callOnScripts('onSkipDialogue', [dialogueCount]);
	}
	
	function getPresencePoints() {
		if (songPoints == 0)
			return "";

		if (songPoints < 0) {
			var aasss = '${songPoints}'.split('');
			aasss.insert(1, ' ');
			return ' - ${aasss.join('')}FP';
		}
		
		return ' - ${songPoints}FP';
	}

	function startSong():Void
	{
		startingSong = false;

		@:privateAccess
		FlxG.sound.playMusic(inst._sound, 1, false);
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		FlxG.sound.music.onComplete = finishSong.bind();
		vocals.play();
		opponentVocals.play();

		setSongTime(Math.max(0, startOnTime - 500));
		startOnTime = 0;

		if(paused) {
			//trace('Oopsie doopsie! Paused sound');
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}

		// Song duration in a float, useful for the time left feature
		songLength = FlxG.sound.music.length;
		FlxTween.tween(timeBar, {alpha: 1}, 0.5, {ease: FlxEase.circOut});
		FlxTween.tween(timeTxt, {alpha: 1}, 0.5, {ease: FlxEase.circOut});

		if (abot != null)
			abot.snd = FlxG.sound.music;

		#if DISCORD_ALLOWED
		// Updating Discord Rich Presence (with Time Left)
		DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")" + getPresencePoints(), iconP2.getCharacter(), true, songLength);
		#end
		setOnScripts('songLength', songLength);
		callOnScripts('onSongStart');
	}

	var debugNum:Int = 0;
	private var noteTypes:Array<String> = [];
	private var eventsPushed:Array<String> = [];
	private function generateSong(dataPath:String):Void
	{
		// FlxG.log.add(ChartParser.parse());
		songSpeed = PlayState.SONG.speed;
		songSpeedType = ClientPrefs.getGameplaySetting('scrolltype');
		switch(songSpeedType)
		{
			case "multiplicative":
				songSpeed = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed');
			case "constant":
				songSpeed = ClientPrefs.getGameplaySetting('scrollspeed');
		}

		var songData = SONG;
		Conductor.bpm = songData.bpm;

		curSong = songData.song;

		vocals = new FlxSound();
		opponentVocals = new FlxSound();
		if (songData.needsVoices) {
			try {
				var playerVocals = Paths.voices(curSong, boyfriend.vocalsFile, songSuffix);
				if (playerVocals == null) playerVocals = Paths.voices(curSong, 'Player', songSuffix);
				vocals.loadEmbedded(playerVocals ?? Paths.voices(curSong, null, songSuffix));
				
				var oppVocals = Paths.voices(curSong, dad.vocalsFile, songSuffix);
				if (oppVocals == null) oppVocals = Paths.voices(curSong, 'Opponent', songSuffix);
				if(oppVocals != null) opponentVocals.loadEmbedded(oppVocals);
			}
			catch (exc:Dynamic) {
				//vocals.loadEmbedded(Paths.voices(curSong, null, songSuffix));
			}
		}

		#if FLX_PITCH
		vocals.pitch = playbackRate;
		opponentVocals.pitch = playbackRate;
		#end
		FlxG.sound.list.add(vocals);
		FlxG.sound.list.add(opponentVocals);

		inst = new FlxSound().loadEmbedded(Paths.inst(curSong, songSuffix));
		FlxG.sound.list.add(inst);

		notes = new FlxTypedGroup<Note>();
		noteGroup.add(notes);

		var noteData:Array<SwagSection>;

		// NEW SHIT
		noteData = songData.notes;

		var file:String = Paths.json(songName + '/events' + songSuffix);
		#if MODS_ALLOWED
		if (FileSystem.exists(Paths.modsJson(songName + '/events' + songSuffix)) || FileSystem.exists(file)) {
		#else
		if (OpenFlAssets.exists(file)) {
		#end
			var eventsData:Array<Dynamic> = Song.loadFromJson('events' + songSuffix, songName).events;
			for (event in eventsData) //Event Notes
				for (i in 0...event[1].length)
					makeEvent(event, i);
		}

		var playingNoteCount:Float = 0;
		var lastStrumTime:Float = 0;

		var isPsychRelease = songData.format == 'psych_v1';

		for (section in noteData)
		{
			for (songNotes in section.sectionNotes)
			{
				var daStrumTime:Float = songNotes[0];
				if (daStrumTime > inst.length)
					continue;
				var daNoteData:Int = Std.int(songNotes[1] % 4);
				var maniaKeys:Int = 4;
				// switch (SONG.mania) {
				// 	case 1, 5, 6: // 6k
				// 		maniaKeys = 6;
				// 		daNoteData = Std.int(songNotes[1] % maniaKeys);

				// 		if (daNoteData > 3)
				// 			daNoteData -= 4;
				// 	case 2, 7: // 7k
				// 		maniaKeys = 7;
				// 		daNoteData = Std.int(songNotes[1] % maniaKeys);

				// 		if (daNoteData > 3)
				// 			daNoteData -= 4;
				// 	case 3, 8: // 9k
				// 		maniaKeys = 9;
				// 		daNoteData = Std.int(songNotes[1] % maniaKeys);

				// 		if (daNoteData > 7)
				// 			daNoteData -= 4;
						
				// 		if (daNoteData > 3)
				// 			daNoteData -= 4;
				// }
				if (songNotes[1] < 0 || songNotes[1] > maniaKeys * 2 - 1) // this should prevent most exe mods from crashing
					continue;
				var gottaHitNote:Bool = section.mustHitSection;

				if (!isPsychRelease) {
					if (songNotes[1] > maniaKeys - 1) {
						gottaHitNote = !section.mustHitSection;
					}
				}
				else {
					gottaHitNote = songNotes[1] < maniaKeys;
				}

				var oldNote:Note;
				if (unspawnNotes.length > 0)
					oldNote = unspawnNotes[Std.int(unspawnNotes.length - 1)];
				else
					oldNote = null;

				var swagNote:Note = new Note(daStrumTime, daNoteData, oldNote);
				swagNote.mustPress = gottaHitNote;
				swagNote.sustainLength = songNotes[2];
				swagNote.gfNote = (section.gfSection && (songNotes[1]<maniaKeys));
				swagNote.noteType = songNotes[3];
				if(!Std.isOfType(songNotes[3], String)) swagNote.noteType = ChartingState.noteTypeList[songNotes[3]]; //Backward compatibility + compatibility with Week 7 charts

				if (noBadNotes && (swagNote.hitCausesMiss || swagNote.hitHealth < 0)) {
					swagNote.destroy();
					continue;
				}

				swagNote.scrollFactor.set();

				var susLength:Float = swagNote.sustainLength;

				susLength = susLength / Conductor.stepCrochet;

				unspawnNotes.push(swagNote);

				if (isPlayerNote(swagNote)) {
					if (daStrumTime - lastStrumTime > 10)
						playingNoteCount++;

					lastStrumTime = daStrumTime;
				}

				var floorSus:Int = Math.floor(susLength);
				if(floorSus > 0) {
					for (susNote in 0...floorSus+1)
					{
						oldNote = unspawnNotes[Std.int(unspawnNotes.length - 1)];

						var sustainNote:Note = new Note(daStrumTime + (Conductor.stepCrochet * susNote), daNoteData, oldNote, true);
						sustainNote.mustPress = gottaHitNote;
						sustainNote.gfNote = (section.gfSection && (songNotes[1]<maniaKeys));
						sustainNote.noteType = swagNote.noteType;
						sustainNote.scrollFactor.set();
						swagNote.tail.push(sustainNote);
						sustainNote.parent = swagNote;
						unspawnNotes.push(sustainNote);
						
						sustainNote.correctionOffset = swagNote.height / 2;
						if(!PlayState.isPixelStage)
						{
							if(oldNote.isSustainNote)
							{
								oldNote.scale.y *= Note.SUSTAIN_SIZE / oldNote.frameHeight;
								oldNote.scale.y /= playbackRate;
								oldNote.updateHitbox();
							}

							if(ClientPrefs.data.downScroll)
								sustainNote.correctionOffset = 0;
						}
						else if(oldNote.isSustainNote)
						{
							oldNote.scale.y /= playbackRate;
							oldNote.updateHitbox();
						}

						if (sustainNote.mustPress) sustainNote.followX += FlxG.width / 2; // general offset
						else if(ClientPrefs.data.middleScroll)
						{
							sustainNote.followX += 310;
							if(daNoteData > 1) //Up and Right
							{
								sustainNote.followX += FlxG.width / 2 + 25;
							}
						}
					}
				}

				if (swagNote.mustPress)
				{
					swagNote.followX += FlxG.width / 2; // general offset
				}
				else if(ClientPrefs.data.middleScroll)
				{
					swagNote.followX += 310;
					if(daNoteData > 1) //Up and Right
					{
						swagNote.followX += FlxG.width / 2 + 25;
					}
				}

				if(!noteTypes.contains(swagNote.noteType)) {
					noteTypes.push(swagNote.noteType);
				}
			}
		}
		songDensity = playingNoteCount == 0 ? 0 : playingNoteCount / (inst.length / playbackRate / 1000) / 2;
		trace("note density score (w/ fp): " + (1 + songDensity));
		for (event in songData.events) //Event Notes
			for (i in 0...event[1].length)
				makeEvent(event, i);

		unspawnNotes.sort(sortByTime);
		generatedMusic = true;
	}

	// called only once per different event (Used for precaching)
	function eventPushed(event:EventNote) {
		eventPushedUnique(event);
		if(eventsPushed.contains(event.event)) {
			return;
		}

		stagesFunc(function(stage:BaseStage) stage.eventPushed(event));
		eventsPushed.push(event.event);
	}

	// called by every event with the same name
	function eventPushedUnique(event:EventNote) {
		switch(event.event) {
			case "Change Character":
				var charType:Int = 0;
				switch(event.value1.toLowerCase()) {
					case 'gf' | 'girlfriend' | '1':
						charType = 2;
					case 'dad' | 'opponent' | '0':
						charType = 1;
					default:
						var val1:Int = Std.parseInt(event.value1);
						if(Math.isNaN(val1)) val1 = 0;
						charType = val1;
				}

				var newCharacter:String = event.value2;
				addCharacterToList(newCharacter, charType);
			
			case 'Play Sound':
				precacheList.set(event.value1, 'sound');
				Paths.sound(event.value1);
		}
		stagesFunc(function(stage:BaseStage) stage.eventPushedUnique(event));
	}

	function eventEarlyTrigger(event:EventNote):Float {
		var returnedValue:Null<Float> = callOnScripts('eventEarlyTrigger', [event.event, event.value1, event.value2, event.strumTime], true, [], [0]);
		if(returnedValue != null && returnedValue != 0 && returnedValue != FunkinLua.Function_Continue) {
			return returnedValue;
		}

		switch(event.event) {
			case 'Kill Henchmen': //Better timing so that the kill sound matches the beat intended
				return 280; //Plays 280ms before the actual position
		}
		return 0;
	}

	public static function sortByTime(Obj1:Dynamic, Obj2:Dynamic):Int
		return FlxSort.byValues(FlxSort.ASCENDING, Obj1.strumTime, Obj2.strumTime);

	function makeEvent(event:Array<Dynamic>, i:Int)
	{
		var subEvent:EventNote = {
			strumTime: event[0] + ClientPrefs.data.noteOffset,
			event: event[1][i][0],
			value1: event[1][i][1],
			value2: event[1][i][2]
		};
		eventNotes.push(subEvent);
		eventPushed(subEvent);
		callOnScripts('onEventPushed', [subEvent.event, subEvent.value1 != null ? subEvent.value1 : '', subEvent.value2 != null ? subEvent.value2 : '', subEvent.strumTime]);
	}

	public var skipArrowStartTween:Bool = false; //for lua
	private function generateStaticArrows(player:Int):Void
	{
		var strumLineX:Float = ClientPrefs.data.middleScroll ? STRUM_X_MIDDLESCROLL : STRUM_X;
		var strumLineY:Float = ClientPrefs.data.downScroll ? (FlxG.height - 150) : 50;
		for (i in 0...4)
		{
			// FlxG.log.add(i);
			var targetAlpha:Float = 1;

			if (!isPlayerStrumNote(player))
			{
				if(!ClientPrefs.data.opponentStrums) targetAlpha = 0;
				else if(ClientPrefs.data.middleScroll) targetAlpha = 0.35;
			}

			var babyArrow:StrumNote = new StrumNote(strumLineX, strumLineY, i, player);
			babyArrow.downScroll = ClientPrefs.data.downScroll;
			if (!isStoryMode && !skipArrowStartTween)
			{
				//babyArrow.y -= 10;
				babyArrow.alpha = 0;
				FlxTween.tween(babyArrow, {/*y: babyArrow.y + 10,*/ alpha: targetAlpha}, 1, {ease: FlxEase.circOut, startDelay: 0.5 + (0.2 * i)});
			}
			else
				babyArrow.alpha = targetAlpha;

			if (!isPlayerStrumNote(player) && ClientPrefs.data.middleScroll) {
				babyArrow.x += 310;
				if (i > 1) { // Up and Right
					babyArrow.x += FlxG.width / 2 + 25;
				}
			}

			if (player == 1)
				playerStrums.add(babyArrow);
			else
			{
				opponentStrums.add(babyArrow);
			}

			if (GameClient.isConnected()) {
				if (!playsAsBF())
					babyArrow.maxAlpha = (player == 0 ? 1 : 0.7);
				else
					babyArrow.maxAlpha = (player == 0 ? 0.7 : 1);
			}

			strumLineNotes.add(babyArrow);
			babyArrow.postAddedToGroup();
		}
	}

	override function openSubState(SubState:FlxSubState)
	{
		if (isCreated) {
			stagesFunc(function(stage:BaseStage) stage.openSubState(SubState));
			if (paused)
			{
				if (FlxG.sound.music != null)
				{
					FlxG.sound.music.pause();
					vocals.pause();
					opponentVocals.pause();
				}

				if (startTimer != null && !startTimer.finished) startTimer.active = false;
				if (finishTimer != null && !finishTimer.finished) finishTimer.active = false;
				if (songSpeedTween != null) songSpeedTween.active = false;

				var chars:Array<Character> = [boyfriend, gf, dad];
				for (char in chars)
					if(char != null && char.colorTween != null)
						char.colorTween.active = false;

				#if LUA_ALLOWED
				for (tween in modchartTweens) tween.active = false;
				for (timer in modchartTimers) timer.active = false;
				#end
			}
		}

		super.openSubState(SubState);
	}

	override function closeSubState()
	{
		if (isCreated) {
			stagesFunc(function(stage:BaseStage) stage.closeSubState());
			if (paused) {
				if (FlxG.sound.music != null && !startingSong) {
					resyncVocals();
				}

				touchPad.visible = true;

				if (startTimer != null && !startTimer.finished)
					startTimer.active = true;
				if (finishTimer != null && !finishTimer.finished)
					finishTimer.active = true;
				if (songSpeedTween != null)
					songSpeedTween.active = true;

				var chars:Array<Character> = [boyfriend, gf, dad];
				for (char in chars)
					if (char != null && char.colorTween != null)
						char.colorTween.active = true;

				#if LUA_ALLOWED
				for (tween in modchartTweens)
					tween.active = true;
				for (timer in modchartTimers)
					timer.active = true;
				#end

				paused = false;
				callOnScripts('onResume');
				resetRPC(startTimer != null && startTimer.finished);
			}
		}

		super.closeSubState();
	}

	override public function onFocus():Void
	{
		if (isCreated && health > 0 && !paused) resetRPC(Conductor.songPosition > 0.0);
		super.onFocus();
	}

	override public function onFocusLost():Void
	{
		#if DISCORD_ALLOWED
		if (isCreated && health > 0 && !paused) DiscordClient.changePresence(detailsPausedText, SONG.song + " (" + storyDifficultyText + ")" + getPresencePoints(), iconP2.getCharacter());
		#end

		super.onFocusLost();
	}

	// Updating Discord Rich Presence.
	function resetRPC(?cond:Bool = false)
	{
		#if DISCORD_ALLOWED
		if (cond)
			DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")" + getPresencePoints(), iconP2.getCharacter(), true, songLength - Conductor.songPosition - ClientPrefs.data.noteOffset);
		else
			DiscordClient.changePresence(detailsText, SONG.song + " (" + storyDifficultyText + ")" + getPresencePoints(), iconP2.getCharacter());
		#end
	}

	public function resyncVocals():Void
	{
		if(finishTimer != null) return;

		trace('resynced vocals at ' + Math.floor(Conductor.songPosition));

		FlxG.sound.music.play();
		#if FLX_PITCH FlxG.sound.music.pitch = playbackRate; #end
		Conductor.songPosition = FlxG.sound.music.time;

		var checkVocals = [vocals, opponentVocals];
		for (voc in checkVocals)
		{
			if (Conductor.songPosition <= vocals.length)
			{
				voc.time = Conductor.songPosition;
				#if FLX_PITCH voc.pitch = playbackRate; #end
				voc.play();
			}
	
		}
	}

	public var paused(default, set):Bool = false;
	function set_paused(v) {
		for (group in [boyfriendGroup, dadGroup, gfGroup]) {
			if (group == null)
				continue;

			for (character in group) {
				if (!(character is Character))
					continue;

				var char:Character = cast(character);

				if (char.sound == null)
					continue;

				if (v)
					char.sound.pause();
				else
					char.sound.resume();
			}
		}
		return paused = v;
	}
	public var canReset:Bool = true;
	var startedCountdown:Bool = false;
	public var canPause:Bool = true;

	public var disableForceShow:Bool = false;

	var lastLagPos:Float = 0;
	var isPlayNoteNear:Bool = false;

	override public function update(elapsed:Float)
	{
		if (!isCreated) {
			if (!asyncLoop.started) {
				asyncLoop.start();
			}

			super.update(elapsed);
			return;
		}

		if (FlxG.keys.justPressed.F7) {
			ClientPrefs.data.showFP = !ClientPrefs.data.showFP;
			ClientPrefs.saveSettings();
			updateScore();
		}

		if (FlxG.keys.justPressed.F2) {
			ClientPrefs.data.disableSubmiting = !ClientPrefs.data.disableSubmiting;
			ClientPrefs.saveSettings();
			Alert.alert("Replay Submiting: " + (ClientPrefs.data.disableSubmiting ? "OFF" : "ON"));
		}
		
		if (!GameClient.isConnected()) {
			if (!ClientPrefs.data.disableLagDetection
				&& !finishingSong
				&& elapsed >= 0.1
				&& Conductor.songPosition > lastLagPos
				&& isPlayNoteNear) {
				setSongTime(Conductor.songPosition - 2000);
				lastLagPos = Conductor.songPosition + 3000; // don't tp for another 3s starting from last lag pos
				Alert.alert("Mod Lag Detected (-2s)");
			}

			if (FlxG.keys.justPressed.F6) {
				swingMode = !swingMode;
			}

			if (FlxG.keys.justPressed.F8 && replayPlayer == null) {
				opponentMode = !opponentMode;
				remove(replayRecorder);
				replayRecorder.destroy();
				songScore = 0;
				boyfriend.isPlayer = !boyfriend.isPlayer;
				dad.isPlayer = !dad.isPlayer;
				addHealth(2);
			}

			if (cpuControlled) {
				var shiftMult = FlxG.keys.pressed.SHIFT ? 3 : 1;
				if (controls.UI_LEFT) {
					if (playbackRate - elapsed * 0.25 * shiftMult > 0)
						playbackRate -= elapsed * 0.25 * shiftMult;
					if (playbackRate < 0.01) {
						playbackRate = 0.01;
					}
					botplayTxt.text = "BOTPLAY\n" + '(${CoolUtil.floorDecimal(playbackRate, 2)}x)';
				}
				else if (controls.UI_RIGHT) {
					playbackRate += elapsed * 0.25 * shiftMult;
					if (playbackRate > 8) {
						playbackRate = 8;
					}
					botplayTxt.text = "BOTPLAY\n" + '(${CoolUtil.floorDecimal(playbackRate, 2)}x)';
				}
				else if (controls.RESET) {
					playbackRate = 1;
				}
			}
		}

		if (FlxG.keys.justPressed.F11 && GameClient.isConnected()) {
			GameClient.reconnect(5); //delay the reconnection for 5 seconds (for testing)
		}

		if (controls.TAUNT && canInput()) {
			var altSuffix = FlxG.keys.pressed.ALT ? '-alt' : '';
			getPlayer().playAnim('taunt' + altSuffix, true);
			if (GameClient.isConnected())
				GameClient.send("charPlay", ["taunt" + altSuffix]);
		}

		if (GameClient.isConnected()) {
			//if player 2 left then go back to lobby // nvm, unreliable on reconnects
			// if (!GameClient.reconnecting && GameClient.room.state.player2.name == "") {
			// 	trace("No one is playing, leaving...");
			// 	endSong();
			// }

			if (canStart && !isReady && (controls.mobileC && FlxG.mouse.justPressed || controls.ACCEPT) && canInput()) {
				isReady = true;
				FlxG.sound.play(Paths.sound('confirmMenu'), 0.5);
				if (ClientPrefs.data.flashing)
					freakyFlicker = FlxFlicker.flicker(waitReadySpr, 0.5, 0.05, true, false, _ -> waitReadySpr.text = "waiting for other player...");
				GameClient.send("playerReady");
			}

			if (waitReady) {
				paused = true;
				FlxG.sound.music.pause();
				vocals.pause();
				opponentVocals.pause();
			}
		}

		/*if (FlxG.keys.justPressed.NINE)
		{
			iconP1.swapOldIcon();
		}*/
		callOnScripts('onUpdate', [elapsed]);

		FlxG.camera.followLerp = 0;
		if(!inCutscene && !paused) {
			//FlxG.camera.followLerp = FlxMath.bound(elapsed * 2.4 * cameraSpeed * playbackRate / (FlxG.updateFramerate / 60), 0, 1);
			FlxG.camera.followLerp = 0.04 * cameraSpeed * playbackRate;
			if(!startingSong && !endingSong && getPlayer().animation.curAnim != null && getPlayer().animation.curAnim.name.startsWith('idle')) {
				boyfriendIdleTime += elapsed;
				if(boyfriendIdleTime >= 0.15) { // Kind of a mercy thing for making the achievement easier to get as it's apparently frustrating to some playerss
					boyfriendIdled = true;
				}
			} else {
				boyfriendIdleTime = 0;
			}
		}

		super.update(elapsed);

		setOnScripts('curDecStep', curDecStep);
		setOnScripts('curDecBeat', curDecBeat);

		if (controls.PAUSE #if android || FlxG.android.justReleased.BACK #end && startedCountdown && canPause && canInput())
		{
			var ret:Dynamic = callOnScripts('onPause', null, true);
			if(ret != FunkinLua.Function_Stop) {
				openPauseMenu();
			}
		}

		// "!inCutscene" it's called a DEBUG button for a reason
		if (controls.justPressed('debug_1') && !endingSong && canInput())
			openChartEditor();

		var mult:Float = FlxMath.lerp(1, iconP1.scale.x, FlxMath.bound(1 - (elapsed * 9 * playbackRate), 0, 1));
		iconP1.scale.set(mult, mult);
		iconP1.updateHitbox();

		var mult:Float = FlxMath.lerp(1, iconP2.scale.x, FlxMath.bound(1 - (elapsed * 9 * playbackRate), 0, 1));
		iconP2.scale.set(mult, mult);
		iconP2.updateHitbox();

		var iconOffset:Int = 26;
		if (health > 2) health = 2;
		else if (health < 0) health = 0;
		iconP1.x = healthBar.barCenter + (150 * iconP1.scale.x - 150) / 2 - iconOffset;
		iconP2.x = healthBar.barCenter - (150 * iconP2.scale.x) / 2 - iconOffset * 2;
		iconP1.animation.curAnim.curFrame = (healthBar.percent < 20) ? 1 : 0;
		iconP2.animation.curAnim.curFrame = (healthBar.percent > 80) ? 1 : 0;

		if (controls.justPressed('debug_2') && !endingSong && canInput())
			openCharacterEditor();
		
		if (startedCountdown && !paused)
		{
			Conductor.songPosition += FlxG.elapsed * 1000 * playbackRate;
			if (Conductor.songPosition >= 0)
			{
				var timeDiff:Float = Math.abs(FlxG.sound.music.time - Conductor.songPosition - Conductor.offset);
				Conductor.songPosition = FlxMath.lerp(Conductor.songPosition, FlxG.sound.music.time, FlxMath.bound(elapsed * 2.5, 0, 1));
				if (timeDiff > 1000 * playbackRate)
					Conductor.songPosition = Conductor.songPosition + 1000 * FlxMath.signOf(timeDiff);
			}
		}

		if (!paused && startingSong)
		{
			if (startedCountdown && Conductor.songPosition >= 0)
				startSong();
			else if(!startedCountdown)
				Conductor.songPosition = -Conductor.crochet * 5;
		}
		else if (!paused && updateTime)
		{
			var curTime:Float = Math.max(0, Conductor.songPosition - ClientPrefs.data.noteOffset);
			songPercent = (curTime / songLength);

			var songCalc:Float = (songLength - curTime);
			if(ClientPrefs.data.timeBarType == 'Time Elapsed') songCalc = curTime;

			var secondsTotal:Int = Math.floor(songCalc / 1000);
			if(secondsTotal < 0) secondsTotal = 0;

			if(ClientPrefs.data.timeBarType != 'Song Name')
				timeTxt.text = FlxStringUtil.formatTime(secondsTotal / playbackRate, false);
		}

		if (camZooming)
		{
			FlxG.camera.zoom = FlxMath.lerp(defaultCamZoom, FlxG.camera.zoom, FlxMath.bound(1 - (elapsed * 3.125 * camZoomingDecay * playbackRate), 0, 1));
			camHUD.zoom = FlxMath.lerp(defaultHUDCamZoom, camHUD.zoom, FlxMath.bound(1 - (elapsed * 3.125 * camZoomingDecay * playbackRate), 0, 1));
		}

		FlxG.watch.addQuick("secShit", curSection);
		FlxG.watch.addQuick("beatShit", curBeat);
		FlxG.watch.addQuick("stepShit", curStep);

		// RESET = Quick Game Over Screen
		if (!GameClient.isConnected() && !ClientPrefs.data.noReset && controls.RESET && canReset && !inCutscene && startedCountdown && !endingSong && canInput() && replayData == null && !cpuControlled)
		{
			subsHealth(9999);
			trace("RESET = True");
		}
		doDeathCheck();

		if (unspawnNotes[0] != null)
		{
			var time:Float = spawnTime * (Conductor.judgePlaybackRate == null || playbackRate < Conductor.judgePlaybackRate ? playbackRate : Conductor.judgePlaybackRate);
			if(songSpeed < 1) time /= songSpeed;
			if(unspawnNotes[0].multSpeed < 1) time /= unspawnNotes[0].multSpeed;

			while (unspawnNotes.length > 0 && unspawnNotes[0].strumTime - Conductor.songPosition < time)
			{
				var dunceNote:Note = unspawnNotes[0];
				notes.insert(0, dunceNote);
				dunceNote.spawned = true;

				callOnLuas('onSpawnNote', [0, dunceNote.noteData, dunceNote.noteType, dunceNote.isSustainNote, dunceNote.strumTime]);
				callOnHScript('onSpawnNote', [dunceNote]);

				unspawnNotes.shift();

				// insert tesla and einstein png here
				// var index:Int = unspawnNotes.indexOf(dunceNote);
				// unspawnNotes.splice(index, 1);
			}
		}

		isPlayNoteNear = false;
		if (generatedMusic)
		{
			if(!inCutscene)
			{
				if(!cpuControlled) {
					keysCheck();
				} else if(getPlayer().animation.curAnim != null && getPlayer().holdTimer > Conductor.stepCrochet * (0.0011 / playbackRate) * getPlayer().singDuration &&
					getPlayer().animation.curAnim.name.startsWith('sing') && !(getPlayer().animation.curAnim.name.endsWith('miss') || getOpponent().isMissing)) {
					getPlayer().dance();
					playerHold = false;
					//boyfriend.animation.curAnim.finish();
				}

				if (GameClient.isConnected() && (!oppHold || endingSong) && getOpponent().animation.curAnim != null
					&& getOpponent().holdTimer > Conductor.stepCrochet * (0.0011 / playbackRate) * getOpponent().singDuration
					&& getOpponent().animation.curAnim.name.startsWith('sing')
					&& !(getOpponent().animation.curAnim.name.endsWith('miss') || getOpponent().isMissing))
				{
					getOpponent().dance();
					//boyfriend.animation.curAnim.finish();
				}

				var forceShowOpStrums = false;
				if(notes.length > 0)
				{
					if(startedCountdown)
					{
						var fakeCrochet:Float = (60 / SONG.bpm) * 1000;
						notes.forEachAlive(function(daNote:Note)
						{
							var strumGroup:FlxTypedGroup<StrumNote> = playerStrums;
							if(!daNote.mustPress) strumGroup = opponentStrums;

							var strum:StrumNote = strumGroup.members[daNote.noteData];
							if (!playsAsBF() && !disableForceShow) {
								forceShowOpStrums = true;
								daNote.visible = true;
								daNote.noteAlpha = 1;
							}
								
							daNote.followStrumNote(strum, fakeCrochet, songSpeed / playbackRate);

							if (GameClient.isConnected() && daNote.strumTime <= Conductor.songPosition) {
								camZooming = true;
							}

							if (isPlayerNote(daNote))
							{
								if (!isPlayNoteNear && daNote.strumTime - Conductor.songPosition < 500)
									isPlayNoteNear = true;

								if(cpuControlled && !daNote.blockHit && daNote.canBeHit && (daNote.isSustainNote || daNote.strumTime <= Conductor.songPosition))
									goodNoteHit(daNote);
							}
							else if (daNote.wasGoodHit && !daNote.hitByOpponent && !daNote.ignoreNote && !GameClient.isConnected())
								opponentNoteHit(daNote);

							if(daNote.isSustainNote && strum.sustainReduce) daNote.clipToStrumNote(strum);

							// Kill extremely late notes and cause misses
							if (Conductor.songPosition - daNote.strumTime > noteKillOffset)
							{
								if (isPlayerNote(daNote) && !cpuControlled &&!daNote.ignoreNote && !endingSong && (daNote.tooLate || !daNote.wasGoodHit))
									noteMiss(daNote);

								daNote.active = false;
								daNote.visible = false;

								//if(!ClientPrefs.data.lowQuality || !cpuControlled) daNote.kill();
								notes.remove(daNote, true);
								daNote.destroy();
							}
						});
					}
					else
					{
						notes.forEachAlive(function(daNote:Note)
						{
							daNote.canBeHit = false;
							daNote.wasGoodHit = false;
						});
					}
				}

				if (forceShowOpStrums) {
					for (strum in opponentStrums) {
						camHUD.visible = true;
						camHUD.alpha = 1;
						strum.alpha = 1;
						strum.visible = true;
					}
				}
			}
			checkEventNote();
		}

		if (!GameClient.isConnected() 
			&& !ClientPrefs.data.disableLagDetection
			&& !finishingSong
			&& elapsed >= 0.1
			&& Conductor.songPosition > lastLagPos
			&& isPlayNoteNear) 
		{
			setSongTime(Conductor.songPosition - 2000);
			lastLagPos = Conductor.songPosition + 3000; // don't tp for another 3s starting from last lag pos
			Alert.alert("Mod Lag Detected (-2s)");
		}

		#if debug
		if(!endingSong && !startingSong) {
			if (FlxG.keys.justPressed.ONE) {
				KillNotes();
				FlxG.sound.music.onComplete();
			}
			if(FlxG.keys.justPressed.TWO) { //Go 10 seconds into the future :O
				setSongTime(Conductor.songPosition + 10000);
				clearNotesBefore(Conductor.songPosition);
			}
		}
		#end

		setOnScripts('cameraX', camFollow.x);
		setOnScripts('cameraY', camFollow.y);
		setOnScripts('botPlay', cpuControlled);
		callOnScripts('onUpdatePost', [elapsed]);

		if (botplayTxt.visible != botplayVisibility)
			botplayTxt.visible = botplayVisibility;

		if (botplayTxt.visible) {
			botplaySine += 180 * elapsed;
			botplayTxt.alpha = 1 - Math.sin((Math.PI * botplaySine) / 180);
		}

		if (Conductor.songPosition >= FlxG.sound.music.length) {
			finishSong();
		}
	}

	function openPauseMenu()
	{
		if (!canPause)
			return;

		FlxG.camera.followLerp = 0;
		touchPad.visible = persistentUpdate = false;
		persistentDraw = true;
		paused = true;

		// 1 / 1000 chance for Gitaroo Man easter egg
		/*if (FlxG.random.bool(0.1))
		{
			// gitaroo man easter egg
			cancelMusicFadeTween();
			FlxG.switchState(() -> new GitarooPause());
		}
		else {*/
		if(FlxG.sound.music != null) {
			FlxG.sound.music.pause();
			vocals.pause();
			opponentVocals.pause();
		}
		if(!cpuControlled)
		{
			for (note in getPlayerStrums())
				if(note.animation.curAnim != null && note.animation.curAnim.name != 'static')
				{
					note.playAnim('static');
					note.resetAnim = 0;
				}
		}
		openSubState(new PauseSubState(getPlayer().getScreenPosition().x, getPlayer().getScreenPosition().y));
		//}

		#if DISCORD_ALLOWED
		DiscordClient.changePresence(detailsPausedText, SONG.song + " (" + storyDifficultyText + ")" + getPresencePoints(), iconP2.getCharacter());
		#end
	}

	public function openChartEditor()
	{
		if (GameClient.isConnected() || redditMod)
			return;

		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		paused = true;
		cancelMusicFadeTween();
		chartingMode = true;
		replayData = null;

		#if DISCORD_ALLOWED
		DiscordClient.changePresence("Chart Editor", null, null, true);
		DiscordClient.resetClientID();
		#end
		
		FlxG.switchState(() -> new ChartingState());
	}

	function openCharacterEditor()
	{
		if (GameClient.isConnected() || redditMod)
			return;

		FlxG.camera.followLerp = 0;
		persistentUpdate = false;
		paused = true;
		replayData = null;
		cancelMusicFadeTween();
		#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end
		FlxG.switchState(() -> new CharacterEditorState(SONG.player2));
	}

	public var isDead:Bool = false; //Don't mess with this on Lua!!!
	function doDeathCheck(?skipHealthCheck:Bool = false) {
		if (!GameClient.isConnected() && ((skipHealthCheck && instakillOnMiss) || (playsAsBF() ? health <= 0 : health >= 2)) && !practiceMode && !isDead && replayPlayer == null)
		{
			var ret:Dynamic = callOnScripts('onGameOver', null, true);
			if(ret != FunkinLua.Function_Stop) {
				getPlayer().stunned = true;
				deathCounter++;

				paused = true;

				vocals.stop();
				opponentVocals.stop();
				FlxG.sound.music.stop();

				persistentUpdate = false;
				persistentDraw = false;
				#if LUA_ALLOWED
				for (tween in modchartTweens) {
					tween.active = true;
				}
				for (timer in modchartTimers) {
					timer.active = true;
				}
				#end

				openSubState(new GameOverSubstate(
					getPlayer().getScreenPosition().x - getPlayer().positionArray[0], 
					getPlayer().getScreenPosition().y - getPlayer().positionArray[1], 
					camFollow.x, camFollow.y,
					(getPlayer().animExists('firstDeath') && getPlayer().animExists('deathLoop') ? getPlayer() : null)
				));

				// FlxG.switchState(() -> new GameOverState(boyfriend.getScreenPosition().x, boyfriend.getScreenPosition().y));

				#if DISCORD_ALLOWED
				// Game Over doesn't get his own variable because it's only used here
				DiscordClient.changePresence("Game Over - " + detailsText, SONG.song + " (" + storyDifficultyText + ")", iconP2.getCharacter());
				#end
				isDead = true;
				return true;
			}
		}
		return false;
	}

	public function tweenCameraZoom(zoom:Float, duration:Float, direct:Bool, ease:Null<Float->Float>) {
		if (cameraTwn != null)
			cameraTwn.cancel();
		cameraTwn = FlxTween.tween(this, {forceCameraZoom: zoom * (direct ? FlxCamera.defaultZoom : stageData.defaultZoom)}, duration, {ease: ease, onComplete: twn -> {cameraTwn = null;}});
	}

	public function tweenCameraToPosition(x:Float, y:Float, duration:Float, ease:Null<Float->Float>) {
		if (cameraTwnX != null)
			cameraTwnX.cancel();
		if (cameraTwnY != null)
			cameraTwnY.cancel();

		cameraTwnX = FlxTween.tween(this, {currentCameraX: x}, duration, {ease: ease});
		cameraTwnY = FlxTween.tween(this, {currentCameraY: y}, duration, {ease: ease});
	}

	public function checkEventNote() {
		while(eventNotes.length > 0) {
			var leStrumTime:Float = eventNotes[0].strumTime;
			if(Conductor.songPosition < leStrumTime) {
				return;
			}

			var value1:String = '';
			if(eventNotes[0].value1 != null)
				value1 = eventNotes[0].value1;

			var value2:String = '';
			if(eventNotes[0].value2 != null)
				value2 = eventNotes[0].value2;

			triggerEvent(eventNotes[0].event, value1, value2, leStrumTime);
			eventNotes.shift();
		}
	}

	public function triggerEvent(eventName:String, value1:String, value2:String, strumTime:Float) {
		var flValue1:Null<Float> = Std.parseFloat(value1);
		var flValue2:Null<Float> = Std.parseFloat(value2);
		if(Math.isNaN(flValue1)) flValue1 = null;
		if(Math.isNaN(flValue2)) flValue2 = null;

		switch(eventName) {
			case 'Must Hit Camera':
				var isFren = value1 == "gf";
				var isDad = isFren ? (SONG.notes[curSection]?.mustHitSection ?? true) != true : value1 == "dad";

				var options = value2.split(",");

				moveCamera(isDad, isFren, Std.parseFloat(options[0]) ?? 4, options[1], Std.parseFloat(options[2]) ?? 0, Std.parseFloat(options[3]) ?? 0);

			case 'Tween Camera Zoom': //brokne
				var s1 = value1.split(",");
				var s2 = value2.split(",");

				var zoom = Std.parseFloat(s1[0]) ?? 1;
				var duration = Conductor.stepCrochet * (Std.parseFloat(s1[1]) ?? 4) / 1000;
				var ease = s2[0] ?? 'linear';
				var isDirectMode = s2[1] ?? 'direct' == 'direct'; // else stage mode

				var easeFunction:Null<Float->Float> = null;
				if (ease != null && ease != "INSTANT") {
					easeFunction = Reflect.field(FlxEase, ease);
				}

				tweenCameraZoom(zoom, duration, isDirectMode, easeFunction);

			case 'Change Camera Bop':
				if (flValue1 == null) flValue1 = DEFAULT_ZOOM_RATE;
				if (flValue2 == null) flValue2 = 1;

				cameraBopIntensity = (DEFAULT_BOP_INTENSITY - 1.0) * flValue2 + 1.0;
				hudCameraZoomIntensity = (DEFAULT_BOP_INTENSITY - 1.0) * flValue2 * 2.0;
				cameraZoomRate = Std.int(flValue1);

			case 'Hey!':
				var value:Int = 2;
				switch(value1.toLowerCase().trim()) {
					case 'bf' | 'boyfriend' | '0':
						value = 0;
					case 'gf' | 'girlfriend' | '1':
						value = 1;
				}

				if(flValue2 == null || flValue2 <= 0) flValue2 = 0.6;

				if(value != 0) {
					if(dad.curCharacter.startsWith('gf') && Paths.formatToSongPath(SONG.song) == 'tutorial') { //Tutorial GF is actually Dad! The GF is an imposter!! ding ding ding ding ding ding ding, dindinding, end my suffering
						dad.playAnim('cheer', true);
						dad.specialAnim = true;
						dad.heyTimer = flValue2;
					} else if (gf != null) {
						gf.playAnim('cheer', true);
						gf.specialAnim = true;
						gf.heyTimer = flValue2;
					}
				}
				if(value != 1) {
					boyfriend.playAnim('hey', true);
					boyfriend.specialAnim = true;
					boyfriend.heyTimer = flValue2;
				}

			case 'Set GF Speed':
				if(flValue1 == null || flValue1 < 1) flValue1 = 1;
				gfSpeed = Math.round(flValue1);

			case 'Add Camera Zoom':
				if(ClientPrefs.data.camZooms && FlxG.camera.zoom < 1.35) {
					if(flValue1 == null) flValue1 = 0.015;
					if(flValue2 == null) flValue2 = 0.03;

					FlxG.camera.zoom += flValue1;
					camHUD.zoom += flValue2;
				}

			case 'Play Animation':
				//trace('Anim to play: ' + value1);
				var char:Character = dad;
				switch(value2.toLowerCase().trim()) {
					case 'bf' | 'boyfriend':
						char = boyfriend;
					case 'gf' | 'girlfriend':
						char = gf;
					default:
						if(flValue2 == null) flValue2 = 0;
						switch(Math.round(flValue2)) {
							case 1: char = boyfriend;
							case 2: char = gf;
						}
				}

				if (char != null)
				{
					char.playAnim(value1, true);
					char.specialAnim = true;
				}

			case 'Camera Follow Pos':
				if(camFollow != null)
				{
					isCameraOnForcedPos = false;
					if(flValue1 != null || flValue2 != null)
					{
						isCameraOnForcedPos = true;
						if(flValue1 == null) flValue1 = 0;
						if(flValue2 == null) flValue2 = 0;
						camFollow.x = flValue1;
						camFollow.y = flValue2;
					}
				}

			case 'Alt Idle Animation':
				var char:Character = dad;
				switch(value1.toLowerCase().trim()) {
					case 'gf' | 'girlfriend':
						char = gf;
					case 'boyfriend' | 'bf':
						char = boyfriend;
					default:
						var val:Int = Std.parseInt(value1);
						if(Math.isNaN(val)) val = 0;

						switch(val) {
							case 1: char = boyfriend;
							case 2: char = gf;
						}
				}

				if (char != null)
				{
					char.idleSuffix = value2;
					char.recalculateDanceIdle();
				}

			case 'Screen Shake':
				var valuesArray:Array<String> = [value1, value2];
				var targetsArray:Array<FlxCamera> = [camGame, camHUD];
				for (i in 0...targetsArray.length) {
					var split:Array<String> = valuesArray[i].split(',');
					var duration:Float = 0;
					var intensity:Float = 0;
					if(split[0] != null) duration = Std.parseFloat(split[0].trim());
					if(split[1] != null) intensity = Std.parseFloat(split[1].trim());
					if(Math.isNaN(duration)) duration = 0;
					if(Math.isNaN(intensity)) intensity = 0;

					if(duration > 0 && intensity != 0) {
						targetsArray[i].shake(intensity, duration);
					}
				}


			case 'Change Character':
				var charType:Int = 0;
				switch(value1.toLowerCase().trim()) {
					case 'gf' | 'girlfriend':
						charType = 2;
					case 'dad' | 'opponent':
						charType = 1;
					default:
						charType = Std.parseInt(value1);
						if(Math.isNaN(charType)) charType = 0;
				}

				switch(charType) {
					case 0:
						if (!ClientPrefs.data.modchartSkinChanges && boyfriend.isSkin)
							return;

						if(boyfriend.curCharacter != value2) {
							if(!boyfriendMap.exists(value2)) {
								addCharacterToList(value2, charType);
							}

							var lastAlpha:Float = boyfriend.alpha;
							boyfriend.alpha = 0.00001;
							boyfriend = boyfriendMap.get(value2);
							boyfriend.alpha = lastAlpha;
							iconP1.changeIcon(boyfriend.healthIcon);
						}
						setOnScripts('boyfriendName', boyfriend.curCharacter);

					case 1:
						if (!ClientPrefs.data.modchartSkinChanges && dad.isSkin)
							return;

						if(dad.curCharacter != value2) {
							if(!dadMap.exists(value2)) {
								addCharacterToList(value2, charType);
							}

							var wasGf:Bool = dad.curCharacter.startsWith('gf-') || dad.curCharacter == 'gf';
							var lastAlpha:Float = dad.alpha;
							dad.alpha = 0.00001;
							dad = dadMap.get(value2);
							if(!dad.curCharacter.startsWith('gf-') && dad.curCharacter != 'gf') {
								if(wasGf && gf != null) {
									gf.visible = true;
								}
							} else if(gf != null) {
								gf.visible = false;
							}
							dad.alpha = lastAlpha;
							iconP2.changeIcon(dad.healthIcon);
						}
						setOnScripts('dadName', dad.curCharacter);

					case 2:
						if(gf != null)
						{
							if(gf.curCharacter != value2)
							{
								if(!gfMap.exists(value2)) {
									addCharacterToList(value2, charType);
								}

								var lastAlpha:Float = gf.alpha;
								gf.alpha = 0.00001;
								gf = gfMap.get(value2);
								gf.alpha = lastAlpha;
							}
							setOnScripts('gfName', gf.curCharacter);
						}
				}
				reloadHealthBarColors();

			case 'Change Scroll Speed':
				if (songSpeedType != "constant")
				{
					if(flValue1 == null) flValue1 = 1;
					if(flValue2 == null) flValue2 = 0;

					var newValue:Float = SONG.speed * ClientPrefs.getGameplaySetting('scrollspeed') * flValue1;
					if(flValue2 <= 0)
						songSpeed = newValue;
					else
						songSpeedTween = FlxTween.tween(this, {songSpeed: newValue}, flValue2 / playbackRate, {ease: FlxEase.linear, onComplete:
							function (twn:FlxTween)
							{
								songSpeedTween = null;
							}
						});
				}

			case 'Set Property':
				try
				{
					var split:Array<String> = value1.split('.');
					if(split.length > 1) {
						LuaUtils.setVarInArray(LuaUtils.getPropertyLoop(split), split[split.length-1], value2);
					} else {
						LuaUtils.setVarInArray(this, value1, value2);
					}
				}
				catch(e:Dynamic)
				{
					if (e.message != null)
						addTextToDebug('ERROR ("Set Property" Event) - ' + e.message.substr(0, e.message.indexOf('\n')), FlxColor.RED);
				}
			
			case 'Play Sound':
				if(flValue2 == null) flValue2 = 1;
				FlxG.sound.play(Paths.sound(value1), flValue2);
		}
		
		stagesFunc(function(stage:BaseStage) stage.eventCalled(eventName, value1, value2, flValue1, flValue2, strumTime));
		callOnScripts('onEvent', [eventName, value1, value2, strumTime]);
	}

	var prevMustHit:Null<Bool> = null;
	function moveCameraSection(?sec:Null<Int>):Void {
		if(sec == null) sec = curSection;
		if(sec < 0) sec = 0;

		if(SONG.notes[sec] == null) return;
		if(prevMustHit != null && prevMustHit == SONG.notes[sec].mustHitSection) return;
		prevMustHit = SONG.notes[sec].mustHitSection;

		moveCamera(SONG.notes[sec].mustHitSection != true, SONG.notes[sec].gfSection);
	}

	var aLookAt:Int = 1;

	var cameraTwn:FlxTween;
	var cameraTwnX:FlxTween;
	var cameraTwnY:FlxTween;
	public function moveCamera(isDad:Bool, ?toGirlfren:Bool = false, ?duration:Float, ?ease:String, ?tX:Float, ?tY:Float)
	{
		if (ease == "INSTANT")
			FlxG.camera.followLerp = 0;

		if (toGirlfren && gf != null) {
			camFollow.setPosition(tX + gf.getMidpoint().x, tY + gf.getMidpoint().y);
			camFollow.x += gf.cameraPosition[0] + girlfriendCameraOffset[0];
			camFollow.y += gf.cameraPosition[1] + girlfriendCameraOffset[1];
			tweenCamIn();
			callOnScripts('onMoveCamera', ['gf']);
			return;
		}

		if(isDad)
		{
			camFollow.setPosition(tX + dad.getMidpoint().x + 150, tY + dad.getMidpoint().y - 100);
			camFollow.x += dad.cameraPosition[0] + opponentCameraOffset[0];
			camFollow.y += dad.cameraPosition[1] + opponentCameraOffset[1];
			tweenCamIn();
			aLookAt = 0;
			callOnScripts('onMoveCamera', ['dad']);
		}
		else
		{
			camFollow.setPosition(tX + boyfriend.getMidpoint().x - 100, tY + boyfriend.getMidpoint().y - 100);
			camFollow.x -= boyfriend.cameraPosition[0] - boyfriendCameraOffset[0];
			camFollow.y += boyfriend.cameraPosition[1] + boyfriendCameraOffset[1];

			if (Paths.formatToSongPath(SONG.song) == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1)
			{
				cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
					function (twn:FlxTween)
					{
						cameraTwn = null;
					}
				});
			}

			aLookAt = 1;

			callOnScripts('onMoveCamera', ['boyfriend']);
		}
	}

	public function tweenCamIn() {
		if (Paths.formatToSongPath(SONG.song) == 'tutorial' && cameraTwn == null && FlxG.camera.zoom != 1.3) {
			cameraTwn = FlxTween.tween(FlxG.camera, {zoom: 1.3}, (Conductor.stepCrochet * 4 / 1000), {ease: FlxEase.elasticInOut, onComplete:
				function (twn:FlxTween) {
					cameraTwn = null;
				}
			});
		}
	}

	var finishingSong:Bool = false;
	public function finishSong(?ignoreNoteOffset:Bool = false):Void
	{
		if (finishingSong) return;
		finishingSong = true;

		updateTime = false;
		FlxG.sound.music.volume = 0;
		vocals.volume = 0;
		vocals.pause();
		opponentVocals.volume = 0;
		opponentVocals.pause();
		if(ClientPrefs.data.noteOffset <= 0 || ignoreNoteOffset) {
			endCallback();
		} else {
			finishTimer = new FlxTimer().start(ClientPrefs.data.noteOffset / 1000, function(tmr:FlxTimer) {
				endCallback();
			});
		}
	}

	public var skipResults = false;

	public var transitioning = false;
	public function endSong()
	{
		mobileControls.instance.visible = #if !android touchPad.visible = #end false;
		if (redditMod) {
			health = 0;
			doDeathCheck();
			return false;
		}

		songPoints = online.FunkinPoints.calcFP(ratingPercent, songMisses, songDensity, totalNotesHit, maxCombo);

		//Should kill you if you tried to cheat
		if(!startingSong) {
			notes.forEach(function(daNote:Note) {
				if(daNote.strumTime < songLength - Conductor.safeZoneOffset) {
					subsHealth(0.05 * healthLoss);
				}
			});
			for (daNote in unspawnNotes) {
				if(daNote.strumTime < songLength - Conductor.safeZoneOffset) {
					subsHealth(0.05 * healthLoss);
				}
			}

			if(doDeathCheck()) {
				return false;
			}
		}

		timeBar.visible = false;
		timeTxt.visible = false;
		canPause = false;
		endingSong = true;
		camZooming = false;
		inCutscene = false;
		updateTime = false;

		deathCounter = 0;
		seenCutscene = false;

		#if ACHIEVEMENTS_ALLOWED
		if(achievementObj != null)
			return false;
		else
		{
			var noMissWeek:String = WeekData.getWeekFileName() + '_nomiss';
			var achieve:String = checkForAchievement([noMissWeek, 'ur_bad', 'ur_good', 'hype', 'two_keys', 'toastie', 'debugger', '1000combo']);
			if(achieve != null) {
				startAchievement(achieve);
				return false;
			}
		}
		#end

		var ret:Dynamic = callOnScripts('onEndSong', null, true);
		if(ret != FunkinLua.Function_Stop && !transitioning)
		{
			replayData = null;

			var prevHighscore = Highscore.getScore(SONG.song, storyDifficulty);

			#if !switch
			var percent:Float = ratingPercent;
			var gainedPoints:Float = 0;
			if(Math.isNaN(percent)) percent = 0;
			if (!isInvalidScore() && finishingSong) {
				Highscore.saveScore(SONG.song, songScore, storyDifficulty, percent);
				var offlinePoints = online.FunkinPoints.save(ratingPercent, songMisses, songDensity, totalNotesHit, maxCombo);
				if (!online.network.FunkinNetwork.loggedIn)
					gainedPoints = offlinePoints;
				if (replayRecorder != null)
					gainedPoints = replayRecorder.save();
			}
			#end
			playbackRate = 1;

			if (chartingMode)
			{
				openChartEditor();
				return false;
			}

			if (!GameClient.isConnected() && replayPlayer != null) {
				online.gui.Alert.alert("Calculated Points from Replay", "+" + songPoints);
			}

			if (GameClient.isConnected()) {
				Lib.application.window.resizable = true;
				FlxG.sound.playMusic(Paths.music('freakyMenu'));
				if (isInvalidScore()) online.gui.Alert.alert("Calculated Points", "+" + songPoints);
				online.states.ResultsState.gainedPoints = gainedPoints;
				if (!skipResults)
					FlxG.switchState(() -> new online.states.ResultsState());
				else
					FlxG.switchState(() -> new online.states.RoomState());
			}
			else if (isStoryMode)
			{
				campaignScore += songScore;
				campaignMisses += songMisses;

				storyPlaylist.remove(storyPlaylist[0]);

				if (storyPlaylist.length <= 0)
				{
					Mods.loadTopMod();
					FlxG.sound.playMusic(Paths.music('freakyMenu'));
					#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end

					cancelMusicFadeTween();
					if(FlxTransitionableState.skipNextTransIn) {
						CustomFadeTransition.nextCamera = null;
					}
					FlxG.switchState(() -> new StoryMenuState());

					// if ()
					if(!ClientPrefs.getGameplaySetting('practice') && !isInvalidScore()) {
						StoryMenuState.weekCompleted.set(WeekData.weeksList[storyWeek], true);
						Highscore.saveWeekScore(WeekData.getWeekFileName(), campaignScore, storyDifficulty);

						FlxG.save.data.weekCompleted = StoryMenuState.weekCompleted;
						FlxG.save.flush();
					}
					changedDifficulty = false;
				}
				else
				{
					var difficulty:String = Difficulty.getFilePath();

					trace('LOADING NEXT SONG');
					trace(Paths.formatToSongPath(PlayState.storyPlaylist[0]) + difficulty);

					FlxTransitionableState.skipNextTransIn = true;
					FlxTransitionableState.skipNextTransOut = true;
					prevCamFollow = camFollow;

					PlayState.loadSong(PlayState.storyPlaylist[0] + difficulty, PlayState.storyPlaylist[0]);
					FlxG.sound.music.stop();

					cancelMusicFadeTween();
					LoadingState.loadAndSwitchState(new PlayState());
				}
			}
			else
			{
				trace('WENT BACK TO FREEPLAY??');
				Mods.loadTopMod();
				#if DISCORD_ALLOWED DiscordClient.resetClientID(); #end

				cancelMusicFadeTween();
				if(FlxTransitionableState.skipNextTransIn) {
					CustomFadeTransition.nextCamera = null;
				}
				FreeplayState.gainedPoints = gainedPoints;
				FlxG.switchState(() -> new online.states.ResultsSoloState({
					hitNotes: songHits,
					combo: maxCombo,
					sicks: songSicks,
					goods: songGoods,
					bads: songBads,
					shits: songShits,
					misses: songMisses,
					score: songScore,
					accuracy: ratingPercent,
					isHighscore: songScore > prevHighscore,
					difficultyName: Difficulty.getString(),
					songName: SONG.song,
					character: playsAsBF() ? boyfriend.curCharacter : dad.curCharacter,
					points: songPoints
				}));
				changedDifficulty = false;
			}
			transitioning = true;
		}
		return true;
	}

	#if ACHIEVEMENTS_ALLOWED
	var achievementObj:AchievementPopup = null;
	function startAchievement(achieve:String) {
		achievementObj = new AchievementPopup(achieve, camOther);
		achievementObj.onFinish = achievementEnd;
		add(achievementObj);
		trace('Giving achievement ' + achieve);
	}
	function achievementEnd():Void
	{
		achievementObj = null;
		if(endingSong && !inCutscene) {
			endSong();
		}
	}
	#end

	public function KillNotes() {
		while(notes.length > 0) {
			var daNote:Note = notes.members[0];
			daNote.active = false;
			daNote.visible = false;

			//if(!ClientPrefs.data.lowQuality || !cpuControlled) daNote.kill();
			notes.remove(daNote, true);
			daNote.destroy();
		}
		unspawnNotes = [];
		eventNotes = [];
	}

	public var totalPlayed:Int = 0;
	public var totalNotesHit:Float = 0.0;

	public var showCombo:Bool = false;
	public var showComboNum:Bool = true;
	public var showRating:Bool = true;
	public var noteTimingRating:FlxText;
	public var noteTimingRatingTween:FlxTween;

	// Stores Ratings and Combo Sprites in a group
	public var comboGroup:FlxSpriteGroup;
	// Stores HUD Objects in a Group
	public var uiGroup:FlxSpriteGroup;
	// Stores Note Objects in a Group
	public var noteGroup:FlxTypedGroup<FlxBasic>;

	// stores the last judgement object
	var lastRating:FlxSprite;
	var lastRatingOP:FlxSprite;
	// stores the last combo sprite object
	var lastCombo:FlxSprite;
	// stores the last combo score objects in an array
	var lastScore:Array<FlxSprite> = [];
	
	var lastScoreOP:Array<FlxSprite> = [];

	private function cachePopUpScore()
	{
		var uiPrefix:String = '';
		var uiSuffix:String = '';
		if (stageUI != "normal")
		{
			uiPrefix = '${stageUI}UI/';
			if (PlayState.isPixelStage) uiSuffix = '-pixel';
		}

		for (rating in ratingsData)
			Paths.image(uiPrefix + rating.image + uiSuffix);
		for (i in 0...10)
			Paths.image(uiPrefix + 'num' + i + uiSuffix);
	}

	function getComboOffset(isOP:Bool = false) {
		if (!GameClient.isConnected()) {
			return ClientPrefs.data.comboOffset;
		}

		var asBF = playsAsBF();
		if (isOP) {
			asBF = !asBF;
		}

		if (!asBF)
			return ClientPrefs.data.comboOffsetOP1;
		else
			return ClientPrefs.data.comboOffsetOP2;
	}

	private function popUpScoreOP(ratingImage:String) {
		var placement:Float = FlxG.width * 0.35;
		if (GameClient.isConnected()) {
			placement = FlxG.width * (0.30 + (!playsAsBF() ? 0.1 : -0.1));
		}

		var uiPrefix:String = "";
		var uiSuffix:String = '';
		var antialias:Bool = ClientPrefs.data.antialiasing;

		if (stageUI != "normal") {
			uiPrefix = '${stageUI}UI/';
			if (PlayState.isPixelStage)
				uiSuffix = '-pixel';
			antialias = !isPixelStage;
		}

		if (ClientPrefs.data.popUpRating){
		var rating:FlxSprite = new FlxSprite();
		rating.loadGraphic(Paths.image(uiPrefix + ratingImage + uiSuffix));
		rating.cameras = [camHUD];
		rating.screenCenter();
		rating.x = placement - 40;
		rating.y -= 60;
		rating.acceleration.y = 550 * playbackRate * playbackRate;
		rating.velocity.y -= FlxG.random.int(140, 175) * playbackRate;
		rating.velocity.x -= FlxG.random.int(0, 10) * playbackRate;
		rating.visible = (!ClientPrefs.data.hideHud && showRating);
		rating.x += getComboOffset(true)[0];
		rating.y -= getComboOffset(true)[1];
		rating.antialiasing = antialias;

		if (!ClientPrefs.data.comboStacking) {
			if (lastRatingOP != null)
				lastRatingOP.kill();
			lastRatingOP = rating;
		}
		comboGroup.add(rating);

		if (!PlayState.isPixelStage) {
			rating.setGraphicSize(Std.int(rating.width * 0.7));
		}
		else {
			rating.setGraphicSize(Std.int(rating.width * daPixelZoom * 0.85));
		}

		rating.updateHitbox();

		var seperatedScore:Array<Int> = [];

		if (opCumboo >= 1000) {
			seperatedScore.push(Math.floor(opCumboo / 1000) % 10);
		}
		seperatedScore.push(Math.floor(opCumboo / 100) % 10);
		seperatedScore.push(Math.floor(opCumboo / 10) % 10);
		seperatedScore.push(opCumboo % 10);

		if (lastScoreOP != null) {
			while (lastScoreOP.length > 0) {
				lastScoreOP[0].kill();
				lastScoreOP.remove(lastScoreOP[0]);
			}
		}

		var daLoop:Int = 0;
		var xThing:Float = 0;
		for (i in seperatedScore) {
			var numScore:FlxSprite = new FlxSprite().loadGraphic(Paths.image(uiPrefix + 'num' + Std.int(i) + uiSuffix));
			numScore.cameras = [camHUD];
			numScore.screenCenter();
			numScore.x = placement + (43 * daLoop) - 90 + getComboOffset(true)[2];
			numScore.y += 80 - getComboOffset(true)[3];

			if (!ClientPrefs.data.comboStacking)
				lastScoreOP.push(numScore);

			if (!PlayState.isPixelStage)
				numScore.setGraphicSize(Std.int(numScore.width * 0.5));
			else
				numScore.setGraphicSize(Std.int(numScore.width * daPixelZoom));
			numScore.updateHitbox();

			numScore.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
			numScore.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
			numScore.velocity.x = FlxG.random.float(-5, 5) * playbackRate;
			numScore.visible = !ClientPrefs.data.hideHud;
			numScore.antialiasing = antialias;

			if (showComboNum)
				comboGroup.add(numScore);

			FlxTween.tween(numScore, {alpha: 0}, 0.2 / playbackRate, {
				onComplete: function(tween:FlxTween) {
					numScore.destroy();
				},
				startDelay: Conductor.crochet * 0.002 / playbackRate
			});

			daLoop++;
			if (numScore.x > xThing)
				xThing = numScore.x;
		}

		FlxTween.tween(rating, {alpha: 0}, 0.2 / playbackRate, {
			startDelay: Conductor.crochet * 0.001 / playbackRate,
			onComplete: function(tween:FlxTween) {
				rating.destroy();
			}
		});
	}
	}

	private function popUpScore(note:Note = null):Rating
	{
		var noteDiffNoAbs:Float = note.strumTime - (Conductor.judgeSongPosition ?? Conductor.songPosition) + ClientPrefs.getRatingOffset();
		var noteDiff:Float = Math.abs(noteDiffNoAbs);
		getPlayerVocals().volume = 1;

		var placement:Float = FlxG.width * 0.35;
		if (GameClient.isConnected()) {
			placement = FlxG.width * (0.30 + (playsAsBF() ? 0.1 : -0.1)); 
		}
		var rating:FlxSprite = new FlxSprite();
		var score:Int = 350;

		//tryna do MS based judgment due to popular demand
		var daRating:Rating = Conductor.judgeNote(ratingsData, noteDiff / (Conductor.judgePlaybackRate ?? playbackRate));

		totalNotesHit += daRating.ratingMod;
		note.ratingMod = daRating.ratingMod;
		if(!note.ratingDisabled) daRating.hits++;
		note.rating = daRating.name;
		score = daRating.score;

		if(daRating.noteSplash && !note.noteSplashData.disabled)
			spawnNoteSplashOnNote(note);

		//if(!practiceMode && !cpuControlled) {
		songScore += score;
		switch (note.rating) {
			case "sick":
				songSicks++;
			case "good":
				songGoods++;
			case "bad":
				songBads++;
			case "shit":
				songShits++;
				combo = 0;
		}

		if(!note.ratingDisabled)
		{
			songHits++;
			totalPlayed++;
			RecalculateRating(false);
		}

		if (!practiceMode && !cpuControlled) {
			GameClient.send("addScore", score);
			GameClient.send("addHitJudge", note.rating);
		}
		//}

		var uiPrefix:String = "";
		var uiSuffix:String = '';
		var antialias:Bool = ClientPrefs.data.antialiasing;

		if (stageUI != "normal")
		{
			uiPrefix = '${stageUI}UI/';
			if (PlayState.isPixelStage) uiSuffix = '-pixel';
			antialias = !isPixelStage;
		}

		if (ClientPrefs.data.popUpRating){
		rating.loadGraphic(Paths.image(uiPrefix + daRating.image + uiSuffix));
		rating.cameras = [camHUD];
		rating.screenCenter();
		rating.x = placement - 40;
		rating.y -= 60;
		rating.acceleration.y = 550 * playbackRate * playbackRate;
		rating.velocity.y -= FlxG.random.int(140, 175) * playbackRate;
		rating.velocity.x -= FlxG.random.int(0, 10) * playbackRate;
		rating.visible = (!ClientPrefs.data.hideHud && showRating);
		rating.x += getComboOffset()[0];
		rating.y -= getComboOffset()[1];
		rating.antialiasing = antialias;

		var comboSpr:FlxSprite = new FlxSprite().loadGraphic(Paths.image(uiPrefix + 'combo' + uiSuffix));
		comboSpr.cameras = [camHUD];
		comboSpr.screenCenter();
		comboSpr.x = placement;
		comboSpr.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
		comboSpr.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
		comboSpr.visible = !ClientPrefs.data.hideHud;
		comboSpr.x += getComboOffset()[0];
		comboSpr.y -= getComboOffset()[1];
		comboSpr.antialiasing = antialias;
		comboSpr.y += 60;
		comboSpr.velocity.x += FlxG.random.int(1, 10) * playbackRate;
		comboSpr.ID = combo;

		comboGroup.add(rating);
		
		if (!ClientPrefs.data.comboStacking)
		{
			if (lastRating != null) lastRating.kill();
			lastRating = rating;
		}

		if (!PlayState.isPixelStage)
		{
			rating.setGraphicSize(Std.int(rating.width * 0.7));
			comboSpr.setGraphicSize(Std.int(comboSpr.width * 0.7));
		}
		else
		{
			rating.setGraphicSize(Std.int(rating.width * daPixelZoom * 0.85));
			comboSpr.setGraphicSize(Std.int(comboSpr.width * daPixelZoom * 0.85));
		}

		comboSpr.updateHitbox();
		rating.updateHitbox();

		// i miss kade engine
		if (ClientPrefs.data.showNoteTiming && (!ClientPrefs.data.hideHud && showRating) && noteTimingRating == null) {
			add(noteTimingRating = new FlxText(0, 0, 0, "0ms"));
		}
		else if (noteTimingRating == null) {
			noteTimingRating = new FlxText(0, 0, 0, "0ms");
		}
		switch (daRating.name) {
			case 'shit' | 'bad':
				noteTimingRating.color = FlxColor.RED;
			case 'good':
				noteTimingRating.color = FlxColor.LIME;
			case 'sick':
				noteTimingRating.color = FlxColor.CYAN;
		}
		noteTimingRating.borderStyle = OUTLINE;
		noteTimingRating.borderSize = 1;
		noteTimingRating.borderColor = FlxColor.BLACK;
		noteTimingRating.text = FlxMath.roundDecimal(noteDiffNoAbs / (Conductor.judgePlaybackRate ?? playbackRate), 3) + "ms";
		noteTimingRating.size = 20;
		noteTimingRating.camera = camHUD;
		noteTimingRating.alpha = 1;
		noteTimingRating.active = true;

		if (noteTimingRatingTween != null) {
			noteTimingRatingTween.cancel();
		}

		noteTimingRating.x = comboSpr.x + 100;
		noteTimingRating.y = comboSpr.y + comboSpr.height;
		noteTimingRating.acceleration.y = 600;
		noteTimingRating.velocity.y -= 150;
		noteTimingRating.velocity.x += comboSpr.velocity.x;

		var colorCombo:Null<FlxColor> = null;
		if (ClientPrefs.data.colorRating) {
			if (songMisses == 0) {
				if (songShits > 0)
					colorCombo = COLOR_SHIT;
				else if (songBads > 0)
					colorCombo = COLOR_BAD;
				else if (songGoods > 0)
					colorCombo = COLOR_GOOD;
				else if (songSicks > 0)
					colorCombo = COLOR_SICK;
			} 
		}

		var seperatedScore:Array<Int> = [];

		if(combo >= 1000) {
			seperatedScore.push(Math.floor(combo / 1000) % 10);
		}
		seperatedScore.push(Math.floor(combo / 100) % 10);
		seperatedScore.push(Math.floor(combo / 10) % 10);
		seperatedScore.push(combo % 10);

		var daLoop:Int = 0;
		var xThing:Float = 0;
		if (showCombo)
		{
			comboGroup.add(comboSpr);
		}
		if (!ClientPrefs.data.comboStacking)
		{
			if (lastCombo != null) lastCombo.kill();
			lastCombo = comboSpr;
		}
		if (lastScore != null)
		{
			while (lastScore.length > 0)
			{
				lastScore[0].kill();
				lastScore.remove(lastScore[0]);
			}
		}
		for (i in seperatedScore)
		{
			var numScore:FlxSprite = new FlxSprite().loadGraphic(Paths.image(uiPrefix + 'num' + Std.int(i) + uiSuffix));
			numScore.cameras = [camHUD];
			numScore.screenCenter();
			numScore.x = placement + (43 * daLoop) - 90 + getComboOffset()[2];
			numScore.y += 80 - getComboOffset()[3];
			
			if (!ClientPrefs.data.comboStacking)
				lastScore.push(numScore);

			if (!PlayState.isPixelStage) numScore.setGraphicSize(Std.int(numScore.width * 0.5));
			else numScore.setGraphicSize(Std.int(numScore.width * daPixelZoom));
			numScore.updateHitbox();

			numScore.acceleration.y = FlxG.random.int(200, 300) * playbackRate * playbackRate;
			numScore.velocity.y -= FlxG.random.int(140, 160) * playbackRate;
			numScore.velocity.x = FlxG.random.float(-5, 5) * playbackRate;
			numScore.visible = !ClientPrefs.data.hideHud;
			numScore.antialiasing = antialias;

			//if (combo >= 10 || combo == 0)
			if(showComboNum)
				comboGroup.add(numScore);

			FlxTween.tween(numScore, {alpha: 0}, 0.2 / playbackRate, {
				onComplete: function(tween:FlxTween)
				{
					numScore.destroy();
				},
				startDelay: Conductor.crochet * 0.002 / playbackRate
			});

			daLoop++;
			if(numScore.x > xThing) xThing = numScore.x;

			if (colorCombo != null)
				numScore.color = colorCombo;
		}
		comboSpr.x = xThing + 50;
		FlxTween.tween(rating, {alpha: 0}, 0.2 / playbackRate, {
			startDelay: Conductor.crochet * 0.001 / playbackRate
		});

		FlxTween.tween(comboSpr, {alpha: 0}, 0.1 / playbackRate, {
			onComplete: function(tween:FlxTween)
			{
				comboSpr.destroy();
				rating.destroy();
			},
			startDelay: Conductor.crochet * 0.002 / playbackRate
		});

		if (ClientPrefs.data.showNoteTiming) {
			noteTimingRatingTween = FlxTween.tween(noteTimingRating, {alpha: 0}, 0.2 / playbackRate, {
				startDelay: Conductor.crochet * 0.001 / playbackRate,
				onComplete: (t) -> noteTimingRating.active = false
			});
		}
	}

		if (ClientPrefs.data.colorRating) {
			switch (daRating.name) {
				case 'shit':
					rating.color = COLOR_SHIT;
				case 'bad':
					rating.color = COLOR_BAD;
				case 'good':
					rating.color = COLOR_GOOD;
				case 'sick':
					rating.color = COLOR_SICK;
			}
		}

		return daRating;
	}

	public var strumsBlocked:Array<Bool> = [];
	
	private function onKeyPress(event:KeyboardEvent):Void
	{
		var eventKey:FlxKey = event.keyCode;
		var key:Int = getKeyFromEvent(keysArray, eventKey);
		if (!controls.controllerMode && FlxG.keys.checkStatus(eventKey, JUST_PRESSED)) keyPressed(key);
	}

	@:unreflective
	private function keyPressed(key:Int)
	{
		if (!canInput())
			return;

		if (!cpuControlled && startedCountdown && !paused && key > -1)
		{
			if (notes.length > 0 && !getPlayer().stunned && generatedMusic && !endingSong)
			{
				//more accurate hit time for the ratings?
				var lastTime:Float = Conductor.songPosition;
				if(Conductor.songPosition >= 0) Conductor.songPosition = FlxG.sound.music.time;

				var canMiss:Bool = !ClientPrefs.getGhostTapping();

				// heavily based on my own code LOL if it aint broke dont fix it
				var pressNotes:Array<Note> = [];
				var notesStopped:Bool = false;
				var sortedNotesList:Array<Note> = [];
				notes.forEachAlive(function(daNote:Note)
				{
					if (strumsBlocked[daNote.noteData] != true && daNote.canBeHit && isPlayerNote(daNote) &&
						!daNote.tooLate && !daNote.wasGoodHit && !daNote.isSustainNote && !daNote.blockHit)
					{
						if(daNote.noteData == key) sortedNotesList.push(daNote);
						canMiss = true;
					}
				});
				sortedNotesList.sort(sortHitNotes);

				if (sortedNotesList.length > 0) {
					for (epicNote in sortedNotesList)
					{
						for (doubleNote in pressNotes) {
							if (Math.abs(doubleNote.strumTime - epicNote.strumTime) < 1) {
								//if(!ClientPrefs.data.lowQuality || !cpuControlled) doubleNote.kill();
								notes.remove(doubleNote, true);
								doubleNote.destroy();
							} else
								notesStopped = true;
						}

						// eee jack detection before was not super good
						if (!notesStopped) {
							goodNoteHit(epicNote);
							pressNotes.push(epicNote);
						}

					}
				}
				else {
					callOnScripts('onGhostTap', [key]);
					if (canMiss && !getPlayer().stunned) noteMissPress(key);
				}

				// I dunno what you need this for but here you go
				//									- Shubs

				// Shubs, this is for the "Just the Two of Us" achievement lol
				//									- Shadow Mario
				if(!keysPressed.contains(key)) keysPressed.push(key);

				//more accurate hit time for the ratings? part 2 (Now that the calculations are done, go back to the time it was before for not causing a note stutter)
				Conductor.songPosition = lastTime;
			}

			var spr:StrumNote = getPlayerStrums().members[key];
			if(strumsBlocked[key] != true && spr != null && spr.animation.curAnim.name != 'confirm')
			{
				GameClient.send("strumPlay", ["pressed", key, 0]);
				spr.playAnim('pressed');
				spr.resetAnim = 0;
			}
			callOnScripts('onKeyPress', [key]);
		}
	}

	public static function sortHitNotes(a:Note, b:Note):Int
	{
		if (a.lowPriority && !b.lowPriority)
			return 1;
		else if (!a.lowPriority && b.lowPriority)
			return -1;

		return FlxSort.byValues(FlxSort.ASCENDING, a.strumTime, b.strumTime);
	}

	private function onKeyRelease(event:KeyboardEvent):Void
	{
		var eventKey:FlxKey = event.keyCode;
		var key:Int = getKeyFromEvent(keysArray, eventKey);
		//trace('Pressed: ' + eventKey);

		if(!controls.controllerMode && key > -1) keyReleased(key);
	}

	@:unreflective
	private function keyReleased(key:Int)
	{
		if (!canInput())
			return;

		if(!cpuControlled && startedCountdown && !paused)
		{
			var spr:StrumNote = getPlayerStrums().members[key];
			if(spr != null)
			{
				GameClient.send("strumPlay", ["static", key, 0]);
				spr.playAnim('static');
				spr.resetAnim = 0;
			}
			callOnScripts('onKeyRelease', [key]);
		}
	}

	public static function getKeyFromEvent(arr:Array<String>, key:FlxKey):Int
	{
		if(key != NONE)
		{
			for (i in 0...arr.length)
			{
				var note:Array<FlxKey> = Controls.instance.keyboardBinds[arr[i]];
				for (noteKey in note)
					if(key == noteKey)
						return i;
			}
		}
		return -1;
	}

	private function onButtonPress(button:TouchButton, ids:Array<MobileInputID>):Void
	{
		if (ids.filter(id -> id.toString().startsWith("EXTRA")).length > 0 || ids.filter(id -> id.toString().startsWith("TAUNT")).length > 0)
			return;

		var buttonCode:Int = (ids[0].toString().startsWith('NOTE')) ? ids[0] : ids[1];
		callOnScripts('onButtonPressPre', [buttonCode]);
		if (button.justPressed) keyPressed(buttonCode);
		callOnScripts('onButtonPress', [buttonCode]);
	}

	private function onButtonRelease(button:TouchButton, ids:Array<MobileInputID>):Void
	{
		if (ids.filter(id -> id.toString().startsWith("EXTRA")).length > 0 || ids.filter(id -> id.toString().startsWith("TAUNT")).length > 0)
			return;

		var buttonCode:Int = (ids[0].toString().startsWith('NOTE')) ? ids[0] : ids[1];
		callOnScripts('onButtonReleasePre', [buttonCode]);
		if(buttonCode > -1) keyReleased(buttonCode);
		callOnScripts('onButtonRelease', [buttonCode]);
	}

	// Hold notes
	@:unreflective
	private function keysCheck():Void
	{
		if (!canInput())
			return;

		// HOLDING
		var holdArray:Array<Bool> = [];
		var pressArray:Array<Bool> = [];
		var releaseArray:Array<Bool> = [];
		for (key in keysArray)
		{
			holdArray.push(controls.pressed(key));
			pressArray.push(controls.justPressed(key));
			releaseArray.push(controls.justReleased(key));
		}

		// TO DO: Find a better way to handle controller inputs, this should work for now
		if(controls.controllerMode && pressArray.contains(true))
			for (i in 0...pressArray.length)
				if(pressArray[i] && strumsBlocked[i] != true)
					keyPressed(i);

		if (startedCountdown && !getPlayer().stunned && generatedMusic)
		{
			// rewritten inputs???
			if(notes.length > 0)
			{
				notes.forEachAlive(function(daNote:Note)
				{
					// hold note functions
					if (strumsBlocked[daNote.noteData] != true && daNote.isSustainNote && holdArray[daNote.noteData] && daNote.canBeHit
					&& isPlayerNote(daNote) && !daNote.tooLate && !daNote.wasGoodHit && !daNote.blockHit) {
						goodNoteHit(daNote);
					}
				});
			}

			playerHold = holdArray.contains(true);

			if (playerHold && !endingSong) {
				#if ACHIEVEMENTS_ALLOWED
				var achieve:String = checkForAchievement(['oversinging']);
				if (achieve != null) {
					startAchievement(achieve);
				}
				#end
			} else if (getPlayer().animation.curAnim != null
					&& getPlayer().holdTimer > Conductor.stepCrochet * (0.0011 / playbackRate) * getPlayer().singDuration
					&& getPlayer().animation.curAnim.name.startsWith('sing')
					&& !(getPlayer().animation.curAnim.name.endsWith('miss') || getPlayer().isMissing))
			{
				getPlayer().dance();
				//boyfriend.animation.curAnim.finish();
			}
		}

		// TO DO: Find a better way to handle controller inputs, this should work for now
		if((controls.controllerMode || strumsBlocked.contains(true)) && releaseArray.contains(true))
			for (i in 0...releaseArray.length)
				if(releaseArray[i] || strumsBlocked[i] == true)
					keyReleased(i);
	}

	function noteMiss(daNote:Note):Void { //You didn't hit the key and let it go offscreen, also used by Hurt Notes
		//Dupe note remove
		notes.forEachAlive(function(note:Note) {
			if (daNote != note && isPlayerNote(daNote) && daNote.noteData == note.noteData && daNote.isSustainNote == note.isSustainNote && Math.abs(daNote.strumTime - note.strumTime) < 1) {
				//if(!ClientPrefs.data.lowQuality || !cpuControlled) note.kill();
				notes.remove(note, true);
				note.destroy();
			}
		});

		final end:Note = daNote.isSustainNote ? daNote.parent.tail[daNote.parent.tail.length - 1] : daNote.tail[daNote.tail.length - 1];
		if (end != null && end.noteHoldSplash != null) {
			end.noteHoldSplash.kill();
		}
		
		noteMissCommon(daNote.noteData, daNote);
		var result:Dynamic = callOnLuas('noteMiss', [notes.members.indexOf(daNote), daNote.noteData, daNote.noteType, daNote.isSustainNote]);
		if(result != FunkinLua.Function_Stop && result != FunkinLua.Function_StopHScript && result != FunkinLua.Function_StopAll) callOnHScript('noteMiss', [daNote]);
	}

	function noteMissPress(direction:Int = 1):Void //You pressed a key when there was no notes to press for this key
	{
		if(ClientPrefs.getGhostTapping()) return; //fuck it

		noteMissCommon(direction);
		callOnScripts('noteMissPress', [direction]);
	}

	function noteMissCommon(direction:Int, note:Note = null)
	{
		// am i the only one that kinda hears the rayman 3 selection sound there
		FlxG.sound.play(Paths.soundRandom('missnote', 1, 3), 0.3);

		// score and data
		var subtract:Float = 0.05;
		if(note != null) subtract = note.missHealth;
		subsHealth(subtract * healthLoss);

		if(instakillOnMiss)
		{
			getPlayerVocals().volume = 0;
			doDeathCheck(true);
		}
		combo = 0;

		if(!practiceMode) {
			songScore -= 10;
			GameClient.send("addScore", -10);
		}
		if(!endingSong) {
			songMisses++;
			GameClient.send("addMiss");
		}
		totalPlayed++;
		RecalculateRating(true);
		if (note != null)
			GameClient.send("noteMiss", [note.strumTime, note.noteData, note.isSustainNote]);

		// play character anims
		var char:Character = getPlayer();
		if ((SONG.notes[curSection] != null && (SONG.notes[curSection].mustHitSection ? playsAsBF() : !playsAsBF()) && SONG.notes[curSection].gfSection)
			|| (note != null && note.gfNote)) {
				char = gf;
		}
		
		if(char != null /*&& char.hasMissAnimations*/)
		{
			var suffix:String = '';
			if(note != null) suffix = note.animSuffix;

			var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, direction)))] + 'miss' + suffix;
			char.playAnim(animToPlay, true);
			GameClient.send("charPlay", [animToPlay, char == gf]);
			
			if(char != gf && combo > 5 && gf != null && gf.animOffsets.exists('sad'))
			{
				gf.playAnim('sad');
				gf.specialAnim = true;
			}
		}
		getPlayerVocals().volume = 0;
	}

	function opponentNoteHit(note:Note):Void
	{
		if (Paths.formatToSongPath(SONG.song) != 'tutorial')
			camZooming = true;

		if (note.noteType == 'Hey!' && getOpponent().animOffsets.exists('hey')) {
			getOpponent().playAnim('hey', true);
			getOpponent().specialAnim = true;
			getOpponent().heyTimer = 0.6;
		} else if(!note.noAnimation) {
			var altAnim:String = note.animSuffix;

			if (playsAsBF()) {
				if (SONG.notes[curSection] != null)
				{
					if (SONG.notes[curSection].altAnim && !SONG.notes[curSection].gfSection) {
						altAnim = '-alt';
					}
				}
			}

			var char:Character = getOpponent();
			var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length-1, note.noteData)))] + altAnim;
			if(note.gfNote) {
				char = gf;
			}

			if(char != null)
			{
				char.playAnim(animToPlay, true);
				char.holdTimer = 0;
			}
		}

		if (SONG.needsVoices)
			getOpponentVocals().volume = 1;

		strumPlayAnim(true, Std.int(Math.abs(note.noteData)), Conductor.stepCrochet * 1.25 / 1000 / playbackRate);
		note.hitByOpponent = true;

		var compat:String = note.mustPress ? 'goodNoteHit' : 'opponentNoteHit';
		var result:Dynamic = callOnLuas(compat, [notes.members.indexOf(note), Math.abs(note.noteData), note.noteType, note.isSustainNote]);
		if(result != FunkinLua.Function_Stop && result != FunkinLua.Function_StopHScript && result != FunkinLua.Function_StopAll) callOnHScript(compat, [note]);

		spawnHoldSplashOnNote(note);

		if (!note.isSustainNote)
		{
			//if(!ClientPrefs.data.lowQuality || !cpuControlled) note.kill();
			notes.remove(note, true);
			note.destroy();
		}
	}

	function goodNoteHit(note:Note):Void
	{
		if (Paths.formatToSongPath(SONG.song) != 'tutorial')
			camZooming = true;

		if (!note.wasGoodHit)
		{
			if(cpuControlled && (note.ignoreNote || note.hitCausesMiss)) return;

			note.wasGoodHit = true;
			if (ClientPrefs.data.hitsoundVolume > 0 && !note.hitsoundDisabled)
				FlxG.sound.play(Paths.sound(note.hitsound), ClientPrefs.data.hitsoundVolume);

			if(note.hitCausesMiss) {
				noteMiss(note);
				if(!note.noteSplashData.disabled && !note.isSustainNote)
					spawnNoteSplashOnNote(note);

				if(!note.noMissAnimation)
				{
					switch(note.noteType) {
						case 'Hurt Note': //Hurt note
							if (getPlayer().animation.getByName('hurt') != null) {
								getPlayer().playAnim('hurt', true);
								getPlayer().specialAnim = true;
							}
					}
				}

				if (!note.isSustainNote)
				{
					//if(!ClientPrefs.data.lowQuality || !cpuControlled) note.kill();
					notes.remove(note, true);
					note.destroy();
				}
				return;
			}

			var rating:Rating = null;
			if (!note.isSustainNote)
			{
				combo++;
				if(combo > 9999) combo = 9999;
				rating = popUpScore(note);

				switch (rating.name) {
					case "sick":
						addHealth(note.hitHealth * healthGain);
					case "good":
						addHealth((note.hitHealth * 0.5) * healthGain);
					case "bad":
						addHealth((note.hitHealth * 0.2) * healthGain);
				}
			}
			else {
				addHealth(note.hitHealth * healthGain);
			}

			GameClient.send("noteHit", [note.strumTime, note.noteData, note.isSustainNote, rating?.image]);

			if(!note.noAnimation) {
				var altAnim:String = note.animSuffix;

				if (!playsAsBF()) {
					if (SONG.notes[curSection] != null) {
						if (SONG.notes[curSection].altAnim && !SONG.notes[curSection].gfSection) {
							altAnim = '-alt';
						}
					}
				}

				var animToPlay:String = singAnimations[Std.int(Math.abs(Math.min(singAnimations.length - 1, note.noteData)))] + altAnim;

				var char:Character = getPlayer();
				var animCheck:String = 'hey';
				if(note.gfNote)
				{
					char = gf;
					animCheck = 'cheer';
				}
				
				if(char != null)
				{
					char.playAnim(animToPlay, true);
					char.holdTimer = 0;

					if (note.noteType == 'Hey!' && char.animOffsets.exists(animCheck)) {
						char.playAnim(animCheck, true);
						char.specialAnim = true;
						char.heyTimer = 0.6;
						GameClient.send("charPlay", [animCheck, note.gfNote, true]);
					} else {
						GameClient.send("charPlay", [animToPlay, note.gfNote]);
					}
				}
			}

			if(!cpuControlled)
			{
				var spr = getPlayerStrums().members[note.noteData];
				GameClient.send("strumPlay", ["confirm", note.noteData, 0]);
				if(spr != null) spr.playAnim('confirm', true);
			}
			else {
				strumPlayAnim(false, Std.int(Math.abs(note.noteData)), Conductor.stepCrochet * 1.25 / 1000 / playbackRate);
			}
			getPlayerVocals().volume = 1;

			var isSus:Bool = note.isSustainNote; //GET OUT OF MY HEAD, GET OUT OF MY HEAD, GET OUT OF MY HEAD
			var leData:Int = Math.round(Math.abs(note.noteData));
			var leType:String = note.noteType;

			var compat:String = note.mustPress ? 'goodNoteHit' : 'opponentNoteHit';
			var result:Dynamic = callOnLuas(compat, [notes.members.indexOf(note), leData, leType, isSus]);
			if(result != FunkinLua.Function_Stop && result != FunkinLua.Function_StopHScript && result != FunkinLua.Function_StopAll) callOnHScript(compat, [note]);

			spawnHoldSplashOnNote(note);

			if (!note.isSustainNote)
			{
				//if(!ClientPrefs.data.lowQuality || !cpuControlled) note.kill();
				notes.remove(note, true);
				note.destroy();
			}
		}
	}

	public function spawnHoldSplashOnNote(note:Note) {
		if (ClientPrefs.data.holdSplashAlpha <= 0)
			return;

		if (note != null) {
			var strum:StrumNote = (note.mustPress ? playerStrums : opponentStrums).members[note.noteData];

			if(strum != null && note.tail.length != 0)
				spawnHoldSplash(note);
		}
	}

	public function spawnHoldSplash(note:Note) {
		var end:Note = note.isSustainNote ? note.parent.tail[note.parent.tail.length - 1] : note.tail[note.tail.length - 1];
		var splash:SustainSplash = grpHoldSplashes.recycle(SustainSplash);
		splash.setupSusSplash((note.mustPress ? playerStrums : opponentStrums).members[note.noteData], note, playbackRate);
		grpHoldSplashes.add(end.noteHoldSplash = splash);
	}

	public function spawnNoteSplashOnNote(note:Note) {
		if (ClientPrefs.data.splashAlpha <= 0)
			return;

		if(note != null) {
			var strum:StrumNote = getPlayerStrums().members[note.noteData];
			if(strum != null)
				spawnNoteSplash(strum.x, strum.y, note.noteData, note);
		}
	}

	public function spawnNoteSplash(x:Float, y:Float, data:Int, ?note:Note = null) {
		var splash:NoteSplash = grpNoteSplashes.recycle(NoteSplash);
		splash.setupNoteSplash(x, y, data, note);
		grpNoteSplashes.add(splash);
	}

	override function destroy() {
		#if LUA_ALLOWED
		for (i in 0...luaArray.length) {
			var lua:FunkinLua = luaArray[0];
			lua.call('onDestroy', []);
			lua.stop();
		}
		luaArray = [];
		FunkinLua.customFunctions.clear();
		#end

		#if HSCRIPT_ALLOWED
		for (script in hscriptArray)
			if(script != null)
			{
				script.call('onDestroy');
				script.destroy();
			}

		while (hscriptArray.length > 0)
			hscriptArray.pop();
		#end

		FlxG.stage.removeEventListener(KeyboardEvent.KEY_DOWN, onKeyPress);
		FlxG.stage.removeEventListener(KeyboardEvent.KEY_UP, onKeyRelease);
		FlxG.animationTimeScale = 1;
		#if FLX_PITCH FlxG.sound.music.pitch = 1; #end
		Note.globalRgbShaders = [];
		backend.NoteTypesConfig.clearNoteTypesData();
		instance = null;
		orderOffset = 0;
		super.destroy();
	}

	public static function cancelMusicFadeTween() {
		if(FlxG.sound.music.fadeTween != null) {
			FlxG.sound.music.fadeTween.cancel();
		}
		FlxG.sound.music.fadeTween = null;
	}

	var lastStepHit:Int = -1;
	override function stepHit()
	{
		if (!isCreated) {
			return;
		}

		super.stepHit();

		if(curStep == lastStepHit) {
			return;
		}

		if (!GameClient.isConnected() && swingMode && (curStep % 4 == 3)) { // here in the funkin crew we call that a functional audio resyncing algorithm
			setSongTime(Conductor.songPosition + Conductor.calculateCrochet(Conductor.bpm) / 4);
		}

		lastStepHit = curStep;
		setOnScripts('curStep', curStep);
		callOnScripts('onStepHit');
	}

	var lastBeatHit:Int = -1;

	override function beatHit()
	{
		if (!isCreated) {
			return;
		}

		if(lastBeatHit >= curBeat) {
			//trace('BEAT HIT: ' + curBeat + ', LAST HIT: ' + lastBeatHit);
			return;
		}

		if (generatedMusic)
			notes.sort(FlxSort.byY, ClientPrefs.data.downScroll ? FlxSort.ASCENDING : FlxSort.DESCENDING);

		iconP1.scale.set(1.2, 1.2);
		iconP2.scale.set(1.2, 1.2);

		iconP1.updateHitbox();
		iconP2.updateHitbox();

		if (gf != null && curBeat % Math.round(gfSpeed * gf.danceEveryNumBeats) == 0 && gf.animation.curAnim != null && !gf.animation.curAnim.name.startsWith("sing") && !gf.stunned)
			gf.dance();
		if (curBeat % boyfriend.danceEveryNumBeats == 0 && boyfriend.animation.curAnim != null && !boyfriend.animation.curAnim.name.startsWith('sing') && !boyfriend.stunned)
			boyfriend.dance();
		if (curBeat % dad.danceEveryNumBeats == 0 && dad.animation.curAnim != null && !dad.animation.curAnim.name.startsWith('sing') && !dad.stunned)
			dad.dance();

		if (camZooming && FlxG.camera.zoom < 1.35 && ClientPrefs.data.camZooms && curBeat % cameraZoomRate == 0)
		{
			FlxG.camera.zoom += (0.015 * camZoomingMult) * cameraBopIntensity * defaultCamZoom;
			camHUD.zoom += (hudCameraZoomIntensity * camZoomingMult) * defaultHUDCamZoom;
		}

		//if (camZooming && FlxG.camera.zoom < 1.35 && ClientPrefs.data.camZooms)
		// {
		// 	FlxG.camera.zoom += 0.015 * camZoomingMult;
		// 	camHUD.zoom += 0.03 * camZoomingMult;
		// }

		super.beatHit();
		lastBeatHit = curBeat;

		setOnScripts('curBeat', curBeat);
		callOnScripts('onBeatHit');
	}

	override function sectionHit()
	{	
		if (!isCreated) {
			return;
		}

		if (SONG.notes[curSection] != null)
		{
			if (generatedMusic && !endingSong && !isCameraOnForcedPos)
				moveCameraSection();

			if (SONG.notes[curSection].changeBPM)
			{
				Conductor.bpm = SONG.notes[curSection].bpm;
				setOnScripts('curBpm', Conductor.bpm);
				setOnScripts('crochet', Conductor.crochet);
				setOnScripts('stepCrochet', Conductor.stepCrochet);
			}
			setOnScripts('mustHitSection', SONG.notes[curSection].mustHitSection);
			setOnScripts('altAnim', SONG.notes[curSection].altAnim);
			setOnScripts('gfSection', SONG.notes[curSection].gfSection);
		}
		super.sectionHit();

		if (abot != null)
			updateABotEye();
		
		setOnScripts('curSection', curSection);
		callOnScripts('onSectionHit');
	}

	#if LUA_ALLOWED
	public function startLuasNamed(luaFile:String)
	{
		#if MODS_ALLOWED
		var luaToLoad:String = Paths.modFolders(luaFile);
		if(!FileSystem.exists(luaToLoad))
			luaToLoad = Paths.getPreloadPath(luaFile);
		
		if(FileSystem.exists(luaToLoad))
		#elseif sys
		var luaToLoad:String = Paths.getPreloadPath(luaFile);
		if(OpenFlAssets.exists(luaToLoad))
		#end
		{
			for (script in luaArray)
				if(script.scriptName == luaToLoad) return false;
	
			new FunkinLua(luaToLoad);
			return true;
		}
		return false;
	}
	#end
	
	#if HSCRIPT_ALLOWED
	public function startHScriptsNamed(scriptFile:String)
	{
		var scriptToLoad:String = Paths.modFolders(scriptFile);
		if(!FileSystem.exists(scriptToLoad))
			scriptToLoad = Paths.getPreloadPath(scriptFile);
		
		if(FileSystem.exists(scriptToLoad))
		{
			if (SScript.global.exists(scriptToLoad)) return false;
	
			initHScript(scriptToLoad);
			return true;
		}
		return false;
	}

	public function initHScript(file:String)
	{
		try
		{
			var newScript:HScript = new HScript(null, file);
			@:privateAccess
			if(newScript.parsingException != null)
			{
				addTextToDebug('ERROR ON LOADING: ${newScript.parsingException.message}', FlxColor.RED);
				newScript.destroy();
				return;
			}

			hscriptArray.push(newScript);
			if(newScript.exists('onCreate'))
			{
				var callValue = newScript.call('onCreate');
				if(!callValue.succeeded)
				{
					for (e in callValue.exceptions)
						if (e != null)
							addTextToDebug('ERROR ($file: onCreate) - ${e.message.substr(0, e.message.indexOf('\n'))}', FlxColor.RED);

					newScript.destroy();
					hscriptArray.remove(newScript);
					if (ClientPrefs.isDebug())
						trace('failed to initialize sscript interp!!! ($file)');
				}
				else if (ClientPrefs.isDebug()) trace('initialized sscript interp successfully: $file');
			}
			
		}
		catch(e)
		{
			addTextToDebug('ERROR ($file) - ' + e.message.substr(0, e.message.indexOf('\n')), FlxColor.RED);
			var newScript:HScript = cast (SScript.global.get(file), HScript);
			if(newScript != null)
			{
				newScript.destroy();
				hscriptArray.remove(newScript);
			}
		}
	}
	#end

	public function callOnScripts(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = psychlua.FunkinLua.Function_Continue;
		if(args == null) args = [];
		if(exclusions == null) exclusions = [];
		if(excludeValues == null) excludeValues = [psychlua.FunkinLua.Function_Continue];

		var result:Dynamic = callOnLuas(funcToCall, args, ignoreStops, exclusions, excludeValues);
		if(result == null || excludeValues.contains(result)) result = callOnHScript(funcToCall, args, ignoreStops, exclusions, excludeValues);
		return result;
	}

	public function callOnLuas(funcToCall:String, args:Array<Dynamic> = null, ignoreStops = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = FunkinLua.Function_Continue;
		#if LUA_ALLOWED
		if(args == null) args = [];
		if(exclusions == null) exclusions = [];
		if(excludeValues == null) excludeValues = [FunkinLua.Function_Continue];

		var len:Int = luaArray.length;
		var i:Int = 0;
		while(i < len)
		{
			var script:FunkinLua = luaArray[i];
			if (script == null) {
				luaArray.remove(script);
				i++;
				continue;
			}

			if(exclusions.contains(script.scriptName))
			{
				i++;
				continue;
			}

			var myValue:Dynamic = script.call(funcToCall, args);
			if((myValue == FunkinLua.Function_StopLua || myValue == FunkinLua.Function_StopAll) && !excludeValues.contains(myValue) && !ignoreStops)
			{
				returnVal = myValue;
				break;
			}
			
			if(myValue != null && !excludeValues.contains(myValue))
				returnVal = myValue;

			if(!script.closed) i++;
			else len--;
		}
		#end
		return returnVal;
	}
	
	public function callOnHScript(funcToCall:String, args:Array<Dynamic> = null, ?ignoreStops:Bool = false, exclusions:Array<String> = null, excludeValues:Array<Dynamic> = null):Dynamic {
		var returnVal:Dynamic = psychlua.FunkinLua.Function_Continue;

		#if HSCRIPT_ALLOWED
		if(exclusions == null) exclusions = new Array();
		if(excludeValues == null) excludeValues = new Array();
		excludeValues.push(psychlua.FunkinLua.Function_Continue);

		var len:Int = hscriptArray.length;
		if (len < 1)
			return returnVal;
		for(i in 0...len)
		{
			var script:HScript = hscriptArray[i];
			if(script == null || !script.exists(funcToCall) || exclusions.contains(script.origin))
				continue;

			var myValue:Dynamic = null;
			try
			{
				var callValue = script.call(funcToCall, args);
				if(!callValue.succeeded)
				{
					var e = callValue.exceptions[0];
					if(e != null)
						FunkinLua.luaTrace('ERROR (${script.origin}: ${callValue.calledFunction}) - ' + e.message.substr(0, e.message.indexOf('\n')), true, false, FlxColor.RED);
				}
				else
				{
					myValue = callValue.returnValue;
					if((myValue == FunkinLua.Function_StopHScript || myValue == FunkinLua.Function_StopAll) && !excludeValues.contains(myValue) && !ignoreStops)
					{
						returnVal = myValue;
						break;
					}
					
					if(myValue != null && !excludeValues.contains(myValue))
						returnVal = myValue;
				}
			}
		}
		#end

		return returnVal;
	}

	public function setOnScripts(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		if(exclusions == null) exclusions = [];
		setOnLuas(variable, arg, exclusions);
		setOnHScript(variable, arg, exclusions);
	}

	public function setOnLuas(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		#if LUA_ALLOWED
		if(exclusions == null) exclusions = [];
		for (script in luaArray) {
			if(exclusions.contains(script.scriptName))
				continue;

			script.set(variable, arg);
		}
		#end
	}

	public function setOnHScript(variable:String, arg:Dynamic, exclusions:Array<String> = null) {
		#if HSCRIPT_ALLOWED
		if(exclusions == null) exclusions = [];
		for (script in hscriptArray) {
			if(exclusions.contains(script.origin))
				continue;

			script.set(variable, arg);
		}
		#end
	}

	function strumPlayAnim(isDad:Bool, id:Int, time:Float) {
		var spr:StrumNote = null;
		if(isDad) {
			spr = getOpponentStrums().members[id];
		} else {
			spr = getPlayerStrums().members[id];
			GameClient.send("strumPlay", ["confirm", id, time]);
		}

		if(spr != null) {
			spr.playAnim('confirm', true);
			spr.resetAnim = time;
		}
	}

	public var ratingName:String = '?';
	public var ratingPercent:Float;
	public var ratingFC:String;
	public function RecalculateRating(badHit:Bool = false) {
		setOnScripts('score', songScore);
		setOnScripts('misses', songMisses);
		setOnScripts('hits', songHits);
		setOnScripts('combo', combo);

		var ret:Dynamic = callOnScripts('onRecalculateRating', null, true);
		if(ret != FunkinLua.Function_Stop)
		{
			ratingName = '?';
			if(totalPlayed != 0) //Prevent divide by 0
			{
				// Rating Percent
				ratingPercent = Math.min(1, Math.max(0, totalNotesHit / totalPlayed));
				//trace((totalNotesHit / totalPlayed) + ', Total: ' + totalPlayed + ', notes hit: ' + totalNotesHit);

				// Rating Name
				ratingName = ratingStuff[ratingStuff.length-1][0]; //Uses last string
				if(ratingPercent < 1)
					for (i in 0...ratingStuff.length-1)
						if(ratingPercent < ratingStuff[i][1])
						{
							ratingName = ratingStuff[i][0];
							break;
						}
			}
			fullComboFunction();
		}
		setOnScripts('rating', ratingPercent);
		setOnScripts('ratingName', ratingName);
		setOnScripts('ratingFC', ratingFC);
		setOnScripts('totalPlayed', totalPlayed);
		setOnScripts('totalNotesHit', totalNotesHit);
		updateScore(badHit); // score will only update after rating is calculated, if it's a badHit, it shouldn't bounce -Ghost
	}

	function fullComboUpdate()
	{
		var sicks:Int = ratingsData[0].hits;
		var goods:Int = ratingsData[1].hits;
		var bads:Int = ratingsData[2].hits;
		var shits:Int = ratingsData[3].hits;

		ratingFC = 'Clear';
		if(songMisses < 1)
		{
			if (shits > 0) ratingFC = 'NM';
			else if (bads > 0) ratingFC = 'FC';
			else if (goods > 0) ratingFC = 'GFC';
			else if (sicks > 0) ratingFC = 'SFC';
		}
		else if (songMisses < 10)
			ratingFC = 'SDCB'; // what the fuck is SDCB
	}

	#if ACHIEVEMENTS_ALLOWED
	private function checkForAchievement(achievesToCheck:Array<String> = null):String
	{
		if(chartingMode) return null;

		var usedPractice:Bool = ClientPrefs.getGameplaySetting('practice') || isInvalidScore();
		for (i in 0...achievesToCheck.length) {
			var achievementName:String = achievesToCheck[i];
			if(!Achievements.isAchievementUnlocked(achievementName) && !isInvalidScore() && Achievements.getAchievementIndex(achievementName) > -1) {
				var unlock:Bool = false;
				if (achievementName == WeekData.getWeekFileName() + '_nomiss') // any FC achievements, name should be "weekFileName_nomiss", e.g: "week3_nomiss";
				{
					if(isStoryMode && campaignMisses + songMisses < 1 && Difficulty.getString().toUpperCase() == 'HARD'
						&& storyPlaylist.length <= 1 && !changedDifficulty && !usedPractice)
						unlock = true;
				}
				else
				{
					switch(achievementName)
					{
						case 'ur_bad':
							unlock = (ratingPercent < 0.2 && !practiceMode);

						case 'ur_good':
							unlock = (ratingPercent >= 1 && !usedPractice);

						case 'roadkill_enthusiast':
							unlock = (Achievements.henchmenDeath >= 50);

						case 'oversinging':
							unlock = (boyfriend.holdTimer >= 10 && !usedPractice);

						case 'hype':
							unlock = (!boyfriendIdled && !usedPractice);

						case 'two_keys':
							unlock = (!usedPractice && keysPressed.length <= 2);

						case 'toastie':
							unlock = (/*ClientPrefs.data.framerate <= 60 &&*/ !ClientPrefs.data.shaders && ClientPrefs.data.lowQuality && !ClientPrefs.data.antialiasing);

						case 'debugger':
							unlock = (Paths.formatToSongPath(SONG.song) == 'test' && !usedPractice);

						case '1000combo':
							unlock = combo > 1000;
					}
				}

				if(unlock) {
					Achievements.unlockAchievement(achievementName);
					return achievementName;
				}
			}
		}
		return null;
	}
	#end

	#if (!flash && sys)
	public var runtimeShaders:Map<String, Array<String>> = new Map<String, Array<String>>();
	public function createRuntimeShader(name:String):FlxRuntimeShader
	{
		if(!ClientPrefs.data.shaders) return new FlxRuntimeShader();

		#if (!flash && MODS_ALLOWED && sys)
		if(!runtimeShaders.exists(name) && !initLuaShader(name))
		{
			FlxG.log.warn('Shader $name is missing!');
			return new FlxRuntimeShader();
		}

		var arr:Array<String> = runtimeShaders.get(name);
		return new FlxRuntimeShader(arr[0], arr[1]);
		#else
		FlxG.log.warn("Platform unsupported for Runtime Shaders!");
		return null;
		#end
	}

	public function initLuaShader(name:String, ?glslVersion:Int = 120)
	{
		if(!ClientPrefs.data.shaders) return false;

		#if (MODS_ALLOWED && !flash && sys)
		if(runtimeShaders.exists(name))
		{
			FlxG.log.warn('Shader $name was already initialized!');
			return true;
		}

		var foldersToCheck:Array<String> = [Paths.mods('shaders/')];
		if(Mods.currentModDirectory != null && Mods.currentModDirectory.length > 0)
			foldersToCheck.insert(0, Paths.mods(Mods.currentModDirectory + '/shaders/'));

		for(mod in Mods.getGlobalMods())
			foldersToCheck.insert(0, Paths.mods(mod + '/shaders/'));
		
		for (folder in foldersToCheck)
		{
			if(FileSystem.exists(folder))
			{
				var frag:String = folder + name + '.frag';
				var vert:String = folder + name + '.vert';
				var found:Bool = false;
				if(FileSystem.exists(frag))
				{
					frag = File.getContent(frag);
					found = true;
				}
				else frag = null;

				if(FileSystem.exists(vert))
				{
					vert = File.getContent(vert);
					found = true;
				}
				else vert = null;

				if(found)
				{
					runtimeShaders.set(name, [frag, vert]);
					//trace('Found shader $name!');
					return true;
				}
			}
		}
		FlxG.log.warn('Missing shader $name .frag AND .vert files!');
		#else
		FlxG.log.warn('This platform doesn\'t support Runtime Shaders!', false, false, FlxColor.RED);
		#end
		return false;
	}
	#end

	function isInvalidScore() {
		return cpuControlled || controls.moodyBlues != null || noBadNotes;
	}

	// MULTIPLAYER STUFF HERE

	public function addHealth(v:Float) {
		if (!PlayState.playsAsBF()) {
			return health -= v;
		}
		return health += v;
	}

	public function subsHealth(v:Float) {
		if (!PlayState.playsAsBF()) {
			return health += v;
		}
		return health -= v;
	}

	public static function playsAsBF() {
		if (GameClient.isConnected()) {
			return GameClient.room.state.swagSides ? GameClient.isOwner : !GameClient.isOwner;
		}
		return !opponentMode;
	}

	public static function isPlayerNote(note:Note):Bool {
		if (playsAsBF()) {
			return note.mustPress;
		}
		return !note.mustPress;
	}

	public static function isPlayerStrumNote(player:Int):Bool {
		if (playsAsBF()) {
			return player == 1;
		}
		return player == 0;
	}

	public static function isCharacterPlayer(character:Character) {
		if (instance?.getPlayer() == null) 
			return character.isPlayer;

		return character == instance.getPlayer();
	}

	public function getPlayerStrums() {
		if (playsAsBF()) {
			return playerStrums;
		}
		return opponentStrums;
	}

	public function getOpponentStrums() {
		if (playsAsBF()) {
			return opponentStrums;
		}
		return playerStrums;
	}

	public function getPlayer() {
		if (!playsAsBF()) {
			return dad;
		}
		return boyfriend;
	}

	public function getOpponent() {
		if (playsAsBF()) {
			return dad;
		}
		return boyfriend;
	}

	public function getPlayerVocals() {
		if (opponentVocals.length <= 0)
			return vocals;

		if (playsAsBF())
			return vocals;
		return opponentVocals;
	}

	public function getOpponentVocals() {
		if (opponentVocals.length <= 0)
			return vocals;

		if (playsAsBF())
			return opponentVocals;
		return vocals;
	}

	function registerMessages() {
		GameClient.initStateListeners(this, this.registerMessages);

		if (!GameClient.isConnected())
			return;

		var player = (GameClient.isOwner ? GameClient.room.state.player1 : GameClient.room.state.player2);
		var op = (GameClient.isOwner ? GameClient.room.state.player2 : GameClient.room.state.player1);

		player.listen("ping", (value, prev) -> {
			Waiter.put(() -> {
				if (callOnScripts('onPing', [player.ping], true) == FunkinLua.Function_Stop)
					return;

				updateScore(false, true);
			});
		});
		op.listen("ping", (value, prev) -> {
			Waiter.put(() -> {
				if (callOnScripts('onPingOpponent', [op.ping], true) == FunkinLua.Function_Stop)
					return;

				updateScoreOpponent(false);
			});
		});

		player.listen("botplay", (value, prev) -> {
			Waiter.put(() -> {
				if (callOnScripts('onOnlineBotplay', [player.ping], true) == FunkinLua.Function_Stop)
					return;

				showBotplay();
			});
		});
		op.listen("botplay", (value, prev) -> {
			Waiter.put(() -> {
				if (callOnScripts('onOnlineBotplayOpponent', [op.ping], true) == FunkinLua.Function_Stop)
					return;

				updateScoreOpponent(false);
			});
		});

		GameClient.room.onMessage("custom", function(message:Array<Dynamic>) {
			if (message.length != 2)
				return;

			Waiter.put(() -> {
				callOnScripts('onMessage', message);
			});
		});

		GameClient.room.onMessage("log", function(message) {
			Waiter.put(() -> {
				Alert.alert("New message", online.util.ShitUtil.parseLog(message).content);
			});
		});

		GameClient.room.onMessage("strumPlay", function(message:Array<Dynamic>) {
			Waiter.put(() -> {
				if (message == null || message[0] == null || message[1] == null || message[2] == null)
					return;

				if (callOnScripts('onMessageStrumPlay', message, true) == FunkinLua.Function_Stop)
					return;

				var spr = getOpponentStrums().members[message[1]];
				if (spr != null) {
					spr.playAnim(message[0] + "", true);
					spr.resetAnim = message[2];
				}
			});
		});

		GameClient.room.onMessage("charPlay", function(message:Array<Dynamic>) {
			Waiter.put(() -> {
				if (message == null || message[0] == null)
					return;

				if (callOnScripts('onMessageCharPlay', message, true) == FunkinLua.Function_Stop)
					return;

				if (message[1] ?? false && gf != null) {
					gf.playAnim(message[0], true);
					if (message[2] ?? false)
						gf.specialAnim = true;
				} else if (!(message[1] ?? false) && getOpponent() != null) {
					getOpponent().playAnim(message[0], true);
					if (message[2] ?? false)
						getOpponent().specialAnim = true;
				}
			});
		});

		GameClient.room.onMessage("noteHit", function(message:Array<Dynamic>) {
			Waiter.put(() -> {
				if (message == null || message[0] == null || message[1] == null || message[2] == null)
					return;

				if (callOnScripts('onMessageNoteHit', message, true) == FunkinLua.Function_Stop)
					return;

				notes.forEachAlive(function(note:Note) {
					if (!isPlayerNote(note)
						&& note.noteData == message[1]
						&& note.isSustainNote == message[2]
						&& Math.abs(note.strumTime - message[0]) < 1) 
					{
						opponentNoteHit(note);
					}
				});

				if (!message[2] && message[3] != null) {
					opCumboo++;
					popUpScoreOP(message[3]);
				}

				RecalculateRatingOpponent(false);
				getOpponentVocals().volume = 1;
			});
		});

		GameClient.room.onMessage("noteMiss", function(message:Array<Dynamic>) {
			Waiter.put(() -> {
				if (message == null || message[0] == null || message[1] == null || message[2] == null)
					return;

				if (callOnScripts('onMessageNoteMiss', message, true) == FunkinLua.Function_Stop)
					return;

				notes.forEachAlive(function(note:Note) {
					if (!isPlayerNote(note)
						&& note.noteData == message[1]
						&& note.isSustainNote == message[2]
						&& Math.abs(note.strumTime - message[0]) < 1) 
					{
						//if(!ClientPrefs.data.lowQuality || !cpuControlled) note.kill();
						unspawnNotes.remove(note);
						note.destroy();
					}
				});

				RecalculateRatingOpponent(true);
				getOpponentVocals().volume = 0;
				opCumboo = 0;
			});
		});

		GameClient.room.onMessage("noteHold", function(message:Null<Bool>) {
			Waiter.put(() -> {
				if (message == null)
					return;

				if (callOnScripts('onMessageNoteHold', [message], true) == FunkinLua.Function_Stop)
					return;

				oppHold = message;
			});
		});

		GameClient.room.onMessage("startSong", function(_) {
			Waiter.put(() -> {
				if (callOnScripts('onMessageStartSong', null, true) == FunkinLua.Function_Stop)
					return;

				isReady = true;
				waitReady = false;
				startCountdown();
			});
		});

		GameClient.room.onMessage("endSong", function(_) {
			Waiter.put(() -> {
				if (callOnScripts('onMessageEndSong', null, true) == FunkinLua.Function_Stop)
					return;

				endSong();
			});
		});

		ChatBox.tryRegisterLogs();
	}

	var opRatingPercent = 0.;
	var opRatingName = "?";
	var opRatingFC:String = "SFC";
	var opCumboo:Int = 0;

	public function RecalculateRatingOpponent(badHit:Bool = false) {
		var op = (GameClient.isOwner ? GameClient.room.state.player2 : GameClient.room.state.player1);

		setOnScripts('scoreOP', op.score);
		setOnScripts('missesOP', op.misses);
		setOnScripts('hitsOP', op.sicks + op.goods + op.bads + op.shits); // may be inaccurate to hits
		setOnScripts('comboOP', opCumboo);

		var ret:Dynamic = callOnScripts('onRecalculateRatingOpponent', null, true);
		if (ret != FunkinLua.Function_Stop) {
			var opTotalPlayed = op.sicks + op.goods + op.bads + op.shits + op.misses; // all the encountered notes
			var opTotalNotesHit = 
				(op.sicks * ratingsData[0].ratingMod) + 
				(op.goods * ratingsData[1].ratingMod) + 
				(op.bads * ratingsData[2].ratingMod) +
				(op.shits * ratingsData[3].ratingMod)
			;

			if (opTotalPlayed != 0) // Prevent divide by 0
			{
				// Rating Percent
				opRatingPercent = Math.min(1, Math.max(0, opTotalNotesHit / opTotalPlayed));

				// Rating Name
				opRatingName = ratingStuff[ratingStuff.length - 1][0]; // Uses last string
				if (opRatingPercent < 1)
					for (i in 0...ratingStuff.length - 1)
						if (opRatingPercent < ratingStuff[i][1]) {
							opRatingName = ratingStuff[i][0];
							break;
						}
			}

			opRatingFC = 'Clear';
			if (op.misses < 1) {
				if (op.shits > 0) opRatingFC = 'NM';
				if (op.bads > 0) opRatingFC = 'FC';
				else if (op.goods > 0) opRatingFC = 'GFC';
				else if (op.sicks > 0) opRatingFC = 'SFC';
			}
			else if (op.misses < 10)
				opRatingFC = 'SDCB';
		}
		updateScoreOpponent(badHit);
		setOnScripts('ratingOP', opRatingPercent);
		setOnScripts('ratingNameOP', opRatingName);
		setOnScripts('ratingFCOP', opRatingFC);
	}

	public function updateScoreOpponent(miss:Bool) {
		var op = (GameClient.isOwner ? GameClient.room.state.player2 : GameClient.room.state.player1);

		var str:String = opRatingName;
		if (op.sicks + op.goods + op.bads + op.shits + op.misses != 0) {
			var percent:Float = CoolUtil.floorDecimal(opRatingPercent * 100, 2);
			str += ' ($percent%) - $opRatingFC';
		}

		(!playsAsBF() ? scoreTxtP2 : scoreTxtP1).text = 
			//op.sicks + " " + op.goods + " " + op.bads + " " + op.shits + " " + op.misses
			op.name + '\nScore: ' + FlxStringUtil.formatMoney(op.score, false) + '\nMisses: ' + op.misses + '\nRating: ' + str + "\nPing: " + op.ping
		;

		callOnScripts('onUpdateScoreOpponent', miss);
	}

	public var scrollXCenter(get, set):Float;
	function get_scrollXCenter() {
		return camGame.scroll.x - FlxG.width / 2;
	}
	function set_scrollXCenter(value) {
		return camGame.scroll.x = value - FlxG.width / 2;
	}

	public var scrollYCenter(get, set):Float;
	function get_scrollYCenter() {
		return camGame.scroll.y - FlxG.height / 2;
	}
	function set_scrollYCenter(value) {
		return camGame.scroll.y = value - FlxG.height / 2;
	}

	public function makeLuaTouchPad(DPadMode:String, ActionMode:String) {
		if(members.contains(luaTouchPad)) return;

		if(!variables.exists("luaTouchPad"))
			variables.set("luaTouchPad", luaTouchPad);

		luaTouchPad = new TouchPad(DPadMode, ActionMode, NONE);
		luaTouchPad.alpha = ClientPrefs.data.controlsAlpha;
	}
	
	public function addLuaTouchPad() {
		if(luaTouchPad == null || members.contains(luaTouchPad)) return;

		var target = LuaUtils.getTargetInstance();
		target.insert(target.members.length + 1, luaTouchPad);
	}

	public function addLuaTouchPadCamera() {
		if(luaTouchPad != null)
			luaTouchPad.cameras = [luaTpadCam];
	}

	public function removeLuaTouchPad() {
		if (luaTouchPad != null) {
			luaTouchPad.kill();
			luaTouchPad.destroy();
			remove(luaTouchPad);
			luaTouchPad = null;
		}
	}

	public function luaTouchPadPressed(button:Dynamic):Bool {
		if(luaTouchPad != null) {
			if(Std.isOfType(button, String))
				return luaTouchPad.buttonPressed(MobileInputID.fromString(button));
			else if(Std.isOfType(button, Array)){
				var FUCK:Array<String> = button; // haxe said "You Can't Iterate On A Dyanmic Value Please Specificy Iterator or Iterable *insert nerd emoji*" so that's the only i foud to fix
				var idArray:Array<MobileInputID> = [];
				for(strId in FUCK)
					idArray.push(MobileInputID.fromString(strId));
				return luaTouchPad.anyPressed(idArray);
			} else
				return false;
		}
		return false;
	}

	public function luaTouchPadJustPressed(button:Dynamic):Bool {
		if(luaTouchPad != null) {
			if(Std.isOfType(button, String))
				return luaTouchPad.buttonJustPressed(MobileInputID.fromString(button));
			else if(Std.isOfType(button, Array)){
				var FUCK:Array<String> = button;
				var idArray:Array<MobileInputID> = [];
				for(strId in FUCK)
					idArray.push(MobileInputID.fromString(strId));
				return luaTouchPad.anyJustPressed(idArray);
			} else
				return false;
		}
		return false;
	}
	
	public function luaTouchPadJustReleased(button:Dynamic):Bool {
		if(luaTouchPad != null) {
			if(Std.isOfType(button, String))
				return luaTouchPad.buttonJustReleased(MobileInputID.fromString(button));
			else if(Std.isOfType(button, Array)){
				var FUCK:Array<String> = button;
				var idArray:Array<MobileInputID> = [];
				for(strId in FUCK)
					idArray.push(MobileInputID.fromString(strId));
				return luaTouchPad.anyJustReleased(idArray);
			} else
				return false;
		}
		return false;
	}

	public function luaTouchPadReleased(button:Dynamic):Bool {
		if(luaTouchPad != null) {
			if(Std.isOfType(button, String))
				return luaTouchPad.buttonReleased(MobileInputID.fromString(button));
			else if(Std.isOfType(button, Array)){
				var FUCK:Array<String> = button;
				var idArray:Array<MobileInputID> = [];
				for(strId in FUCK)
					idArray.push(MobileInputID.fromString(strId));
				return luaTouchPad.anyReleased(idArray);
			} else
				return false;
		}
		return false;
	}
}
