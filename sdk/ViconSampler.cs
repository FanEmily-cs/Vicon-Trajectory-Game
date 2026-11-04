// Small .NET worker: blocking SDK calls never execute on MATLAB's UI thread.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Threading;
using ViconDataStreamSDK.DotNET;

namespace TrajectoryUM {
 public sealed class ViconSampler {
  readonly object gate = new object();
  readonly Queue<double[]> rows = new Queue<double[]>();
  readonly Stopwatch clock = Stopwatch.StartNew();
  readonly string host, subject;
  Client client;
  volatile bool stopping;
  bool connected, valid, recording;
  double lastTime = -1, x = double.NaN, y = double.NaN, epoch;
  string message = "Connecting...";
  public ViconSampler(string server, string body) {
   host=server; subject=body;
   var thread=new Thread(Run); thread.IsBackground=true; thread.Name="ViconTrajectorySampler"; thread.Start();
  }
  public string Message { get { lock(gate) return message; } }
  public double[] Snapshot() {
   lock(gate) return new double[] { connected?1:0, valid && clock.Elapsed.TotalSeconds-lastTime<0.25?1:0, x,y };
  }
  public void BeginRecording() { lock(gate) { rows.Clear(); epoch=clock.Elapsed.TotalSeconds; recording=true; } }
  public double EndRecording() { lock(gate) { recording=false; return clock.Elapsed.TotalSeconds-epoch; } }
  // Flatten rows to avoid MATLAB/.NET rectangular-array indexing differences.
  public double[] Drain() {
   lock(gate) {
    var data=new double[rows.Count*5]; int i=0;
    while(rows.Count>0) { var row=rows.Dequeue(); Array.Copy(row,0,data,i,5); i+=5; }
    return data;
   }
  }
  void Add(double t, double px, double py, bool ok, double frame) {
   if(recording && t>=epoch) rows.Enqueue(new double[]{t-epoch,ok?px:double.NaN,ok?py:double.NaN,ok?1:0,frame});
  }
  void Run() {
   try {
    client=new Client();
    if(stopping) return;
    var result=client.Connect(host);
    if(result.Result!=Result.Success || !client.IsConnected().Connected) throw new Exception("Connection failed: "+result.Result);
    if(client.EnableSegmentData().Result!=Result.Success) throw new Exception("Cannot enable segment data.");
    if(client.SetStreamMode(StreamMode.ServerPush).Result!=Result.Success) throw new Exception("Cannot set ServerPush.");
    client.SetBufferSize(256);
    lock(gate) { connected=true; message="Waiting for "+subject; }
    uint previous=0; bool havePrevious=false; double previousTime=-1;
    while(!stopping) {
     var frameResult=client.GetFrame();
     if(stopping) break;
     if(frameResult.Result!=Result.Success) {
      if(!client.IsConnected().Connected) throw new Exception("Vicon disconnected.");
      Thread.Sleep(1); continue;
     }
     var frame=client.GetFrameNumber();
     if(frame.Result!=Result.Success || (havePrevious && frame.FrameNumber==previous)) { Thread.Sleep(1); continue; }
     var root=client.GetSubjectRootSegmentName(subject);
     bool ok=false; double px=double.NaN, py=double.NaN;
     if(root.Result==Result.Success) {
      var position=client.GetSegmentGlobalTranslation(subject,root.SegmentName);
      if(position.Result==Result.Success && !position.Occluded) {
       px=position.Translation[0]/1000.0; py=position.Translation[1]/1000.0;
       ok=!double.IsNaN(px)&&!double.IsInfinity(px)&&!double.IsNaN(py)&&!double.IsInfinity(py);
      }
     }
     double t=clock.Elapsed.TotalSeconds;
     lock(gate) {
      // Mark dropped frames explicitly so replay cannot bridge a missing interval.
      if(havePrevious && (frame.FrameNumber!=unchecked(previous+1) || t-previousTime>0.25))
       Add(Math.Max(epoch,(previousTime+t)/2),double.NaN,double.NaN,false,double.NaN);
      x=px; y=py; valid=ok; lastTime=t;
      message=ok?"Tracking "+subject:"Rigid body lost or unavailable: "+subject;
      Add(t,px,py,ok,frame.FrameNumber);
     }
     previous=frame.FrameNumber; havePrevious=true; previousTime=t;
    }
   } catch(Exception e) { lock(gate) { message=e.Message; Add(clock.Elapsed.TotalSeconds,double.NaN,double.NaN,false,double.NaN); } }
   finally {
    lock(gate) { connected=false; valid=false; }
    try { if(client!=null) client.Disconnect(); } catch { }
   }
  }
  public void Stop() {
   stopping=true;
   lock(gate) recording=false;
   // Disconnect wakes a pending GetFrame; do not wait on the MATLAB UI thread.
   ThreadPool.QueueUserWorkItem(delegate { try { if(client!=null) client.Disconnect(); } catch { } });
  }
 }
}
