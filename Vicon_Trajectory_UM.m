function fig = Vicon_Trajectory_UM(options)
% VICON_TRAJECTORY_UM  MATLAB source entry, launched directly or by BAT.
% Simulation: Vicon_Trajectory_UM(struct('SIMULATION_MODE',true))
% All timestamps are monotonic seconds from Start (host receive time).
cfg = trajectoryConfig();
appDir=fileparts(mfilename('fullpath'));
configFile=fullfile(appDir,'config.json');
if isfile(configFile)
    cfg=applyOptions(cfg,jsondecode(fileread(configFile)));
end
if nargin > 0
    if ischar(options) || isstring(options)
        assert(strcmp(options,'--simulation'),'Only --simulation is supported.');
        options=struct('SIMULATION_MODE',true);
    end
    cfg=applyOptions(cfg,options);
end
if isempty(cfg.RESULTS_DIR)
    cfg.RESULTS_DIR=fullfile(appDir,'results');
elseif ~java.io.File(cfg.RESULTS_DIR).isAbsolute()
    cfg.RESULTS_DIR=fullfile(appDir,cfg.RESULTS_DIR);
end
assert(cfg.REPLAY_SPEED>0 && cfg.SIM_DURATION>0,'Durations and speed must be positive.');
assert(isscalar(cfg.START_COUNTDOWN_SEC) && isfinite(cfg.START_COUNTDOWN_SEC) && cfg.START_COUNTDOWN_SEC>0, ...
    'Start countdown must be positive.');
assert(all(isfinite([cfg.START_RADIUS_M cfg.FINISH_RADIUS_M cfg.FINISH_HOLD_SEC])) && ...
    cfg.START_RADIUS_M>0 && cfg.FINISH_RADIUS_M>0 && cfg.FINISH_HOLD_SEC>=0, ...
    'Zone radii must be positive; finish hold time must be nonnegative.');
baseDir = fileparts(mfilename('fullpath'));
[reference,points] = generateReferencePath();
arc = [0;cumsum(vecnorm(diff(reference),2,2))];
sampler = []; pollTimer = []; replayTimer = [];
state = 'Ready'; connected = false; tracking = false; closing = false;
data = zeros(0,5); metrics = [NaN NaN NaN];
recordClock = []; replayClock = []; duration = 0; lastSimFrame = -1;
lastUI = tic; resultDir = ''; replayXY = []; replayTime = [];
saveAfterReplay = false;
lastXY=[NaN NaN]; nearStart=false; startDistance=Inf; finishEntry=NaN;
startCountdown=[];
fig = figure('Name','Vicon_Trajectory_UM','NumberTitle','off', ...
    'Color','w','Position',[100 100 1080 690],'MenuBar','none', ...
    'ToolBar','none','Visible',cfg.VISIBLE,'CloseRequestFcn',@closeGame);
ax = axes('Parent',fig,'Position',[.08 .11 .52 .80]); hold(ax,'on');
% Display transform only: horizontal Y, vertical -X. Raw XY is unchanged.
displayReference = toDisplay(reference);
displayPoints = toDisplay(points);
plot(ax,displayReference(:,1),displayReference(:,2),'b-','LineWidth',2);
plot(ax,displayPoints(1,1),displayPoints(1,2),'go','MarkerFaceColor','g','MarkerSize',8);
plot(ax,displayPoints(end,1),displayPoints(end,2),'ro','MarkerFaceColor','r','MarkerSize',8);
text(ax,displayPoints(1,1),displayPoints(1,2)+.12,'START','Color',[0 .5 0]);
text(ax,displayPoints(end,1)+.04,displayPoints(end,2),'END','Color','r');
trail = plot(ax,NaN,NaN,'r-','LineWidth',1.6);
marker = plot(ax,NaN,NaN,'ro','MarkerFaceColor','r','MarkerSize',5);
axis(ax,'equal'); xlim(ax,[-1.8 2]); ylim(ax,[-1.15 1.25]);
set(ax,'XLimMode','manual','YLimMode','manual'); grid(ax,'on');
xlabel(ax,'Y (m)'); ylabel(ax,'-X (m)'); title(ax,'Trajectory Display');
panel = uipanel(fig,'Title','Game Control','FontSize',12, ...
    'BackgroundColor','w','Position',[.65 .06 .33 .89]);
label('Vicon_Trajectory_UM',.91,13);
if cfg.SIMULATION_MODE, modeName='SIMULATION MODE'; else, modeName='LIVE VICON'; end
label(modeName,.85,11);
connectionLabel = label('Vicon Connection Status: Disconnected',.77,10);
trackingLabel = label('Tracking Status: Lost',.71,11);
stateLabel = label('Game Status: Ready',.65,11);
timeLabel = label('Timer: 00:00',.58,16);
zoneLabel=uicontrol(panel,'Style','text','String','Move to START', ...
    'Units','normalized','Position',[.06 .545 .91 .03], ...
    'BackgroundColor','w','HorizontalAlignment','left','FontSize',9);
startButton = uicontrol(panel,'Style','pushbutton','String','Start','Units','normalized', ...
    'Position',[.07 .47 .39 .07],'FontSize',12,'Enable','off','Callback',@startRecording);
finishButton = uicontrol(panel,'Style','pushbutton','String','Finish','Units','normalized', ...
    'Position',[.54 .47 .39 .07],'FontSize',12,'Enable','off','Callback',@finishRecording);
reconnectButton = uicontrol(panel,'Style','pushbutton','String','Reconnect','Units','normalized', ...
    'Position',[.07 .38 .39 .055],'Callback',@connectVicon);
replayButton = uicontrol(panel,'Style','pushbutton','String','Replay','Units','normalized', ...
    'Position',[.54 .38 .39 .055],'Enable','off','Callback',@restartReplay);
meanLabel = label('Mean Error (cm): --',.29,12);
rmseLabel = label('RMSE (cm): --',.23,12);
maxLabel = label('Max Error (cm): --',.17,12);
note = uicontrol(panel,'Style','text','String','Initializing...', ...
    'Units','normalized','Position',[.06 .015 .88 .13], ...
    'BackgroundColor','w','HorizontalAlignment','left','FontSize',9);
% Timer callbacks only drain memory; network calls run in the .NET worker.
pollTimer = timer('Name','ViconTrajectoryPoll','ExecutionMode','fixedSpacing', ...
    'Period',.02,'BusyMode','drop','TimerFcn',@poll,'ErrorFcn',@timerError);
replayTimer = timer('Name','ViconTrajectoryReplay','ExecutionMode','fixedSpacing', ...
    'Period',.02,'BusyMode','drop','TimerFcn',@replayTrajectory,'ErrorFcn',@timerError);
setappdata(fig,'TrajectoryAPI',struct('Start',@startRecording,'Finish',@finishRecording, ...
    'Snapshot',@snapshot,'Reconnect',@connectVicon,'Replay',@restartReplay));
connectVicon(); start(pollTimer);

    function h = label(value,y,sizeValue)
        h = uicontrol(panel,'Style','text','String',value,'Units','normalized', ...
            'Position',[.06 y .91 .06],'BackgroundColor','w', ...
            'HorizontalAlignment','left','FontSize',sizeValue);
    end
    function connectVicon(varargin)
        if any(strcmp(state,{'Recording','Replaying'})), return; end
        if ~isempty(sampler), sampler.Stop(); sampler=[]; end
        connected=false; tracking=false; nearStart=false; lastXY=[NaN NaN]; startCountdown=[];
        if cfg.SIMULATION_MODE
            connected=true; tracking=true;
            set(note,'String','Simulation: automatic countdown and finish. Reconnect resets to START.');
        else
            try
                dll = fullfile(cfg.SDK_DIR,'ViconDataStreamSDK_DotNET.dll');
                assert(isfile(dll),'SDK DLL not found: %s',dll);
                setenv('PATH',[cfg.SDK_DIR pathsep getenv('PATH')]);
                NET.addAssembly(dll);
                helper = fullfile(baseDir,'sdk','ViconSampler.dll');
                if ~isfile(helper), helper=which('ViconSampler.dll'); end
                if ~isfile(helper)
                    helper=fullfile(baseDir,'sdk','ViconSampler.dll');
                    compiler=fullfile(getenv('WINDIR'),'Microsoft.NET','Framework64','v4.0.30319','csc.exe');
                    command=sprintf('"%s" /nologo /target:library /platform:x64 /out:"%s" /reference:"%s" "%s"', ...
                        compiler,helper,dll,fullfile(baseDir,'sdk','ViconSampler.cs'));
                    [status,output]=system(command);
                    assert(status==0,'Helper compilation failed: %s',output);
                end
                NET.addAssembly(helper);
                sampler=TrajectoryUM.ViconSampler(cfg.VICON_SERVER,cfg.RIGID_BODY_NAME);
                set(note,'String','Connecting to Vicon...');
            catch exception
                set(note,'String',['Connection error: ' exception.message]);
            end
        end
        refreshUI();
    end
    function [rows,xy] = getPosition()
        rows=zeros(0,5); xy=[NaN NaN];
        if cfg.SIMULATION_MODE
            connected=true; tracking=true;
            if strcmp(state,'Recording')
                xy=lastXY; tracking=all(isfinite(xy));
                t=toc(recordClock); currentFrame=floor(t*100);
                frames=(lastSimFrame+1:currentFrame)'; lastSimFrame=currentFrame;
                times=frames/100;
                xySim=interp1(arc,reference,min(times/cfg.SIM_DURATION,1)*arc(end));
                xySim=xySim+.018*[sin(times*2.1),cos(times*1.7)];
                valid=true(size(times));
                if ~isempty(cfg.SIM_LOSS_INTERVAL)
                    valid=~(times>=cfg.SIM_LOSS_INTERVAL(1) & times<=cfg.SIM_LOSS_INTERVAL(2));
                end
                xySim(~valid,:)=NaN;
                rows=[times,xySim,double(valid),frames];
                if ~isempty(rows), tracking=logical(rows(end,4)); xy=rows(end,2:3); end
            elseif strcmp(state,'Ready') || ~all(isfinite(lastXY))
                xy=points(1,:); % Simulation is placed at START between rounds.
            else
                xy=lastXY; % Stay at the finish after replay; avoid endless automatic rounds.
            end
        elseif ~isempty(sampler)
            raw=double(sampler.Drain());
            if ~isempty(raw), rows=reshape(raw,5,[])'; end
            latest=double(sampler.Snapshot());
            connected=logical(latest(1)); tracking=logical(latest(2)); xy=latest(3:4);
            if ~strcmp(state,'Finished') || ~connected
                set(note,'String',char(sampler.Message));
            end
        end
        lastXY=xy;
        startDistance=norm(xy-points(1,:));
        nearStart=connected && tracking && all(isfinite(xy)) && startDistance<=cfg.START_RADIUS_M;
    end
    function poll(varargin)
        if closing || strcmp(state,'Replaying'), return; end
        [rows,xy]=getPosition();
        if any(strcmp(state,{'Ready','Finished'}))
            if nearStart
                if isempty(startCountdown), startCountdown=tic; end
                if toc(startCountdown)>=cfg.START_COUNTDOWN_SEC
                    startRecording();
                    return;
                end
            else
                startCountdown=[];
            end
        end
        if strcmp(state,'Recording')
            data=[data;rows];
            duration=toc(recordClock);
            if tracking
                displayXY=toDisplay(xy);
                set(marker,'XData',displayXY(1),'YData',displayXY(2));
            else
                set(marker,'XData',NaN,'YData',NaN);
            end
            % A stale stream has no frames to report loss: retain an explicit gap.
            if ~tracking && (isempty(data) || data(end,4)==1)
                data(end+1,:)=[duration NaN NaN 0 NaN];
            end
            % Require consecutive valid samples inside the finish zone.
            % Use sample timestamps so a slow GUI cannot count as a valid hold.
            for k=1:size(rows,1)
                inside=rows(k,4)==1 && norm(rows(k,2:3)-points(end,:))<=cfg.FINISH_RADIUS_M;
                if ~inside
                    finishEntry=NaN;
                elseif isnan(finishEntry)
                    finishEntry=rows(k,1);
                end
                if inside && rows(k,1)-finishEntry>=cfg.FINISH_HOLD_SEC && nnz(data(:,4)==1)>=3
                    finishRecording();
                    return;
                end
            end
            if ~tracking, finishEntry=NaN; end
        end
        if toc(lastUI)>.10, refreshUI(); lastUI=tic; end
    end
    function startRecording(varargin)
        if ~any(strcmp(state,{'Ready','Finished'})), return; end
        getPosition(); % Recheck freshness at the click, not only at last UI refresh.
        if ~nearStart
            startCountdown=[]; refreshUI(); return;
        end
        % A button/API call cannot bypass the automatic countdown.
        if isempty(startCountdown) || toc(startCountdown)<cfg.START_COUNTDOWN_SEC, return; end
        startCountdown=[];
        data=zeros(0,5); metrics=[NaN NaN NaN]; duration=0; resultDir='';
        replayXY=[]; replayTime=[]; saveAfterReplay=false;
        finishEntry=NaN;
        lastSimFrame=-1; recordClock=tic;
        if ~cfg.SIMULATION_MODE, sampler.BeginRecording(); end
        state='Recording';
        set(trail,'XData',NaN,'YData',NaN); set(marker,'XData',NaN,'YData',NaN);
        if strcmp(pollTimer.Running,'off'), start(pollTimer); end
        refreshUI();
    end
    function finishRecording(varargin)
        if ~strcmp(state,'Recording'), return; end
        stop(pollTimer);
        startCountdown=[];
        duration=toc(recordClock);
        if ~cfg.SIMULATION_MODE && ~isempty(sampler), duration=double(sampler.EndRecording()); end
        [rows,~]=getPosition(); data=[data;rows];
        data=data(data(:,1)<=duration,:);
        state='Replaying'; refreshUI();
        set(marker,'XData',NaN,'YData',NaN);
        try
            resultDir=createResultDirectory();
            saveCSV(); % Save raw data before starting the animation.
        catch exception
            resultDir=''; set(note,'String',['Save failed: ' exception.message]);
        end
        if nnz(data(:,4)==1)<3
            state='Finished'; refreshUI();
            set(note,'String','Too few valid samples (<3). Please start again. Raw data retained.');
            saveResults(); start(pollTimer); return;
        end
        % NaN rows retain occlusion gaps, including missing SDK frames.
        replayXY=data(:,2:3); replayTime=data(:,1);
        replayXY(data(:,4)==0,:)=NaN;
        metrics=calculateError(data(data(:,4)==1,2:3),reference);
        saveAfterReplay=true;
        replayClock=tic; start(replayTimer);
    end
    function restartReplay(varargin)
        if ~strcmp(state,'Finished') || isempty(replayTime) || nnz(data(:,4)==1)<3
            return;
        end
        stop(pollTimer);
        startCountdown=[];
        saveAfterReplay=false; % Reviewing a run does not create or overwrite results.
        state='Replaying';
        set(trail,'XData',NaN,'YData',NaN);
        set(marker,'XData',NaN,'YData',NaN);
        refreshUI();
        replayClock=tic; start(replayTimer);
    end
    function replayTrajectory(varargin)
        if closing || ~strcmp(state,'Replaying'), return; end
        progress=toc(replayClock)*cfg.REPLAY_SPEED;
        count=find(replayTime<=progress,1,'last');
        if ~isempty(count)
            displayXY=toDisplay(replayXY(1:count,:));
            set(trail,'XData',displayXY(:,1),'YData',displayXY(:,2));
            set(marker,'XData',displayXY(end,1),'YData',displayXY(end,2));
        end
        if progress>=duration
            stop(replayTimer); state='Finished'; refreshUI();
            if saveAfterReplay, saveResults(); saveAfterReplay=false; end
            if ~closing, start(pollTimer); end
        end
    end
    function refreshUI()
        if closing, return; end
        if connected, connection='Connected'; else, connection='Disconnected'; end
        if tracking, track='Tracking'; else, track='Lost'; end
        set(connectionLabel,'String',['Vicon Connection Status: ' connection]);
        set(trackingLabel,'String',['Tracking Status: ' track]);
        set(stateLabel,'String',['Game Status: ' state]);
        set(timeLabel,'String',sprintf('Timer: %02d:%02d',floor(duration/60),floor(mod(duration,60))));
        available=any(strcmp(state,{'Ready','Finished'}));
        set(startButton,'Enable','off','String','Start (auto)');
        if strcmp(state,'Recording')
            zoneText=sprintf('Auto finish: within %.0f cm for %.1f s',100*cfg.FINISH_RADIUS_M,cfg.FINISH_HOLD_SEC);
        elseif strcmp(state,'Replaying')
            zoneText='Replaying recorded trajectory';
        elseif nearStart && ~isempty(startCountdown)
            remaining=max(1,ceil(cfg.START_COUNTDOWN_SEC-toc(startCountdown)));
            zoneText=sprintf('Starting in %d s - stay at START',remaining);
            set(startButton,'String',sprintf('Start in %d',remaining));
        elseif connected && tracking && isfinite(startDistance)
            zoneText=sprintf('Move to START: %.0f cm away (zone %.0f cm)',100*startDistance,100*cfg.START_RADIUS_M);
        else
            zoneText='Waiting for valid tracking at START';
        end
        set(zoneLabel,'String',zoneText);
        set(finishButton,'Enable',onoff(strcmp(state,'Recording')));
        set(reconnectButton,'Enable',onoff(available));
        set(replayButton,'Enable',onoff(strcmp(state,'Finished') && ~isempty(replayTime) && nnz(data(:,4)==1)>=3));
        handles=[meanLabel rmseLabel maxLabel]; names={'Mean Error','RMSE','Max Error'};
        for k=1:3
            if strcmp(state,'Finished') && isfinite(metrics(k)), value=sprintf('%.2f',metrics(k));
            else, value='--'; end
            set(handles(k),'String',sprintf('%s (cm): %s',names{k},value));
        end
    end
    function value = onoff(condition)
        if condition, value='on'; else, value='off'; end
    end
    function folder = createResultDirectory()
        if ~isfolder(cfg.RESULTS_DIR), mkdir(cfg.RESULTS_DIR); end
        % tempname suffix prevents collisions even with simultaneous windows.
        [~,unique]=fileparts(tempname(cfg.RESULTS_DIR));
        folder=fullfile(cfg.RESULTS_DIR,[char(datetime('now','Format','yyyy-MM-dd_HH-mm-ss-SSS')) '_' unique]);
        [ok,message]=mkdir(folder); assert(ok,'%s',message);
    end
    function saveCSV()
        output=array2table(data,'VariableNames',{'timestamp','x','y','tracking_valid','frame_number'});
        writetable(output,fullfile(resultDir,'trajectory.csv'));
    end
    function saveResults()
        if isempty(resultDir), return; end
        try
            result=struct('config',cfg,'duration',duration,'metrics_cm',metrics, ...
                'reference',reference,'data',data,'timestamp_basis','Host monotonic receive time, seconds since Start');
            save(fullfile(resultDir,'session.mat'),'result');
            % Export the same fixed axes, adding the displayed final metrics.
            oldTitle=title(ax,sprintf('Trajectory Display | Mean %.2f cm | RMSE %.2f cm | Max %.2f cm',metrics));
            exportgraphics(ax,fullfile(resultDir,'trajectory_result.png'),'Resolution',160);
            set(oldTitle,'String','Trajectory Display');
            set(note,'String',['Saved: ' resultDir]);
            fprintf('Trajectory saved: %s\n',resultDir);
        catch exception
            title(ax,'Trajectory Display'); set(note,'String',['Save failed: ' exception.message]);
        end
    end
    function output = snapshot()
        output=struct('state',state,'data',data,'metrics',metrics,'duration',duration, ...
            'resultDir',resultDir,'connected',connected,'tracking',tracking,'reference',reference, ...
            'nearStart',nearStart,'position',lastXY);
    end
    function timerError(~,event)
        if closing, return; end
        stop(pollTimer); stop(replayTimer);
        if ~isempty(sampler), sampler.EndRecording(); end
        state='Finished'; refreshUI();
        set(note,'String',['Timer error: ' event.Data.Message]);
    end
    function closeGame(varargin)
        if closing, return; end
        closing=true;
        for t={pollTimer,replayTimer}
            if ~isempty(t{1}) && isvalid(t{1}), stop(t{1}); delete(t{1}); end
        end
        if ~isempty(sampler), sampler.Stop(); sampler=[]; end
        delete(fig);
    end
end

function displayXY = toDisplay(xy)
% One consistent transform for reference, live marker, replay and PNG export.
displayXY = [xy(:,2),-xy(:,1)];
end

function cfg = applyOptions(cfg,options)
names=fieldnames(options);
for k=1:numel(names)
    assert(isfield(cfg,names{k}),'Unknown option: %s',names{k});
    cfg.(names{k})=options.(names{k});
end
end

function cfg = trajectoryConfig()
% Defaults; config.json can override these values.
cfg.SIMULATION_MODE = true; % Public default: try the game without Vicon hardware.
cfg.VICON_SERVER = 'localhost';
cfg.RIGID_BODY_NAME = 'STEM_WAND';
cfg.SDK_DIR = 'C:\Program Files\Vicon\DataStream SDK\Win64\dotNET';
cfg.REPLAY_SPEED = 1;
cfg.SIM_DURATION = 20;
cfg.SIM_LOSS_INTERVAL = [7 9];
cfg.RESULTS_DIR = 'results';
cfg.VISIBLE = 'on';
cfg.START_RADIUS_M = .15;
cfg.START_COUNTDOWN_SEC = 3;
cfg.FINISH_RADIUS_M = .15;
cfg.FINISH_HOLD_SEC = .3;
end


function [path, points] = generateReferencePath()
% Fixed laboratory XY coordinates in metres. Maximum sample spacing 5 mm.
points = [-.75 -1.47; .26 -1.47; .26 -.55; -.75 -.55; ...
           .75 .40; -.75 .40; .60 1; -.75 1.60; .75 1.60];
path = points(1,:);
for k = 1:8
    if k == 2
        center = (points(2,:)+points(3,:))/2;
        radius = norm(points(3,:)-points(2,:))/2;
        theta = linspace(-pi/2,pi/2,ceil(pi*radius/.005)+1)';
        section = center + radius*[cos(theta),sin(theta)];
        section([1 end],:) = points([2 3],:);
    else
        u = linspace(0,1,ceil(norm(points(k+1,:)-points(k,:))/.005)+1)';
        section = points(k,:) + u*(points(k+1,:)-points(k,:));
    end
    path = [path; section(2:end,:)]; %#ok<AGROW>
end
end


function [metrics, distances] = calculateError(xy, reference)
% Exact point-to-segment distance for the densely sampled reference polyline.
xy = xy(all(isfinite(xy),2),:);
if isempty(xy), metrics = [NaN NaN NaN]; distances = []; return; end
a = reference(1:end-1,:); v = diff(reference,1,1);
length2 = sum(v.^2,2);
keep = length2 > 0; a = a(keep,:); v = v(keep,:); length2 = length2(keep);
distances = zeros(size(xy,1),1);
for k = 1:size(xy,1)
    offset = xy(k,:) - a;
    u = max(0,min(1,sum(offset.*v,2)./length2));
    distances(k) = sqrt(min(sum((offset-u.*v).^2,2)));
end
metrics = 100*[mean(distances),sqrt(mean(distances.^2)),max(distances)];
end

