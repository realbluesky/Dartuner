import 'dart:html';
import 'dart:math';
import 'dart:typed_data';
import 'dart:web_audio';
import 'package:stagexl/stagexl.dart';

num confidence = 0;
num currentPitch = 0;
int currentNote = 0;
int noteGap = 300;
Flight flight;
Sprite notes, gauge;
int hold = 0;
bool falling = false;
ScriptProcessorNode processor;
Stage stage;
ResourceManager resourceManager  = new ResourceManager();
TextField titleText;
CanvasElement canvas;
double sampleRate;
int buflen, iRing = 0;
List<String> noteStrings = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
List<int> noteRing = new List.filled(5,0);
List<num> pitchRing = new List.filled(5,0);

class Flight extends Sprite implements Animatable {
    int wHeight;
    List colors;
    num vr = 3, spin = 0;
    
    Flight(this.wHeight, this.colors) {
      var i=0;
      var wings = new List(2);
      colors.forEach((c) {
        var wing = new Graphics();
          wing
            ..beginPath()
            ..moveTo(0, 0)
            ..lineTo(0, wHeight)
            ..lineTo(wHeight/9,wHeight)
            ..lineTo(5*wHeight/9,25*wHeight/36)
            ..bezierCurveTo(5*wHeight/9, 0, 5*wHeight/9, wHeight/5, 0, 0)
            ..closePath()
            ..fillColor(c);
          wings[i++] = wing;
          
      });
      
      var eWing = new Shape()
        ..graphics = wings[0]
        ..name='e'
        ..applyCache(0, 0, 5*wHeight~/9, wHeight);
      var wWing = new Shape()
        ..graphics = wings[0]
        ..scaleX = -1
        ..name='w'
        ..applyCache(0, 0, 5*wHeight~/9, wHeight);
      var nWing = new Shape()
        ..scaleX = -1
        ..skewY = PI/2
        ..graphics = wings[1]
        ..name ='n'
        ..applyCache(0, 0, 5*wHeight~/9, wHeight);
      var sWing = new Shape()
        ..skewY = PI/2
        ..graphics = wings[1]
        ..name='s'
        ..applyCache(0, 0, 5*wHeight~/9, wHeight);
      
      var needle = new Shape()
        ..name = 'needle'
        ..y=wHeight+30
        ..x=-3
        ..width=6
        ..alpha = 0
        ..height= this.height - wHeight;
      
      needle.graphics
        ..beginPath()
        ..moveTo(0, 10)
        ..lineTo(0, 380)
        ..closePath()
        ..strokeColor(0xFFCCCCCC, 7);
      needle.applyCache(0, 0, 6, 380);
      
      this
          ..addChild(nWing)
          ..addChild(wWing)        
          ..addChild(sWing)
          ..addChild(eWing)
          ..addChild(needle)
        ;

    }
    
    bool advanceTime(num time) {
      spin = spin + vr/100;
      Shape s = this.getChildByName('s');
      Shape n = this.getChildByName('n');
      Shape e = this.getChildByName('e');
      Shape w = this.getChildByName('w');
      var eS = sin(e.skewY);
      var sS = sin(s.skewY);
      w.skewY = spin;
      n.skewY = spin+PI/2;
      e.skewY = spin;
      s.skewY = spin+PI/2;
      
      if(eS*sin(e.skewY)<0) this.swapChildren(e, w);
      if(sS*sin(s.skewY)<0) this.swapChildren(n, s);
      
      return true;
    }
}

void main() {
  
  canvas = querySelector('#tuner');
  stage = new Stage(canvas, webGL: true, width: 1920, height: 1080, color: 0x00333333);
  stage.scaleMode = StageScaleMode.NO_BORDER;
  stage.align = StageAlign.NONE;

  var renderLoop = new RenderLoop();
    renderLoop.addStage(stage);
  
  /* removed for now, couldn't get it working
  BitmapData.defaultLoadOptions.webp = true;
  resourceManager
      ..addBitmapData('mask', 'mask.png')
      ..load().then(createTuner);   
}

void createTuner(ResourceManager resourceManager) {

 */
    
  flight = new Flight(180, [0xAA00A4E4, 0xAA55DDCA])
    ..x = 960
    ..y = 800
    ..height = 550
    ..pivotY = 800
    ;
  
  //1920/8 300 per note, 73 notes = 21900 width
  notes = new Sprite()
    ..width = 21900
    ..height = 300
    ..alpha = 0
    ..y = 650;
  
  gauge = new Sprite()
    ..name = 'gauge'
    ..width = 500
    ..height = 680
    ..x = 710
    ..y = 300
    ..alpha = 0;
  
  var noteFormat = new TextFormat('Montserrat', 70, 0xFFEEEEEE, align:'center', bold:true);
  var smallFormat = new TextFormat('Montserrat', 25, 0xFFEEEEEE, align:'center');
  var freqFormat = new TextFormat('Montserrat', 35, 0xFFDDDDFF, align:'center');
  
  var curFreqText = new TextField('', freqFormat)
    ..name = 'freqText'
    ..width = 200
    ..x = 150
    ..y = 500;
  
  var target = new Shape()
    ..width=50
    ..height=250
    ..x=225
    ..y=50;
  target.graphics
    ..beginPath()
    ..moveTo(10, 0)
    ..lineTo(10, 250)
    ..moveTo(40, 0)
    ..lineTo(40, 250)
    ..closePath()
    ..strokeColor(0xFFEEEEEE, 3);
  target.applyCache(0, 0, 50, 250);
  
  gauge
    ..addChild(curFreqText)
    ..addChild(target);
  
  /* would like to draw gradient mask, but fails, as does resourceManager, fails with
   * StageXL render engine : WebGL
      WebGL: INVALID_VALUE: texImage2D: width or height out of range
      WebGL: INVALID_FRAMEBUFFER_OPERATION: clear: the internalformat of the attached texture is not color-renderable
      WebGL: INVALID_FRAMEBUFFER_OPERATION: drawElements: the internalformat of the attached texture is not color-renderable
      ... 100 or so of those
      [.WebGLRenderingContext]GL ERROR :GL_INVALID_VALUE : glRenderbufferStorage: dimensions too large
      WebGL: too many errors, no more errors will be reported to the console for this context.
      
  var gradient = new GraphicsGradient.linear(0, 0, 1920, 0)
    ..addColorStop(0, 0xFFFFFFFF)
    ..addColorStop(0.5, 0x00FFFFFF)
    ..addColorStop(1, 0xFFFFFFFF);
  var gradShape = new Shape();
  gradShape.graphics
          ..beginPath()
          ..rect(0, 0, 1920, 300)
          ..closePath()
          ..fillGradient(gradient)
          ;
  var bitmapData = new BitmapData(1920, 300, true, 0x00000000)
    ..draw(gradShape);
    
  var alphaMask = new AlphaMaskFilter(resourceManager.getBitmapData('mask'));
  notes.filters = [alphaMask];
    
  */
  
  for(var i=0; i<73; i++) {
    var n = noteStrings[i%12];
    var sharp = false;
    if(n.length>1) { //get sharp
      n = n.substring(0, 1);
      sharp = true;
    }
    var octave = i~/12+1; //start on C1
    var f = frequencyFromNoteNumber(i+24); //C1 is MIDI 24
    var noteText = new TextField(n, noteFormat)
      ..width = noteGap
      ..x = i*noteGap
      ..alpha = .5
      ..cacheAsBitmap = true;
    
    var octText = new TextField(octave.toString(), smallFormat)
          ..width = 40
          ..x = i*noteGap+165
          ..y = 50
          ..alpha = .5
          ..cacheAsBitmap = true;
    
    if(sharp) {
      var sharpText = new TextField('#', smallFormat)
        ..width = 40
        ..x = i*noteGap+165
        ..y = 10
        ..alpha = .5
        ..cacheAsBitmap = true; 
      
      notes.addChild(sharpText);
    }
    
    var freqText = new TextField(f.floor().toString() + 'Hz', smallFormat)
      ..width = noteGap
      ..x = i*noteGap
      ..y = 70
      ..alpha = .5
      ..cacheAsBitmap = true;
    
    notes
      ..addChild(noteText)
      ..addChild(octText)
      ..addChild(freqText);
    
  }
  
  titleText = new TextField('DarTuner', noteFormat)
    ..y = 350
    ..width = 400
    ..x = 760;
  
  stage
    ..addChild(flight)
    ..addChild(notes)
    ..addChild(gauge)
    ..addChild(titleText);
  stage.juggler.add(flight);
  
  AudioContext audioContext = new AudioContext();
  sampleRate = audioContext.sampleRate;
 
  //get audio stream
  window.navigator.getUserMedia(audio:true).then((stream) {
    MediaStreamAudioSourceNode mediaStreamSource = audioContext.createMediaStreamSource(stream);
    
    //strip high freq noise
    BiquadFilterNode lowPass = audioContext.createBiquadFilter()
        ..type = 'lowpass'
        ..frequency.value = 4186 //C8
        ;
    
    processor = audioContext.createScriptProcessor(2048, 1, 1)
         ..onAudioProcess.listen((AudioProcessingEvent e) {
            Float32List data = e.inputBuffer.getChannelData(0);
            tune(data, sampleRate);
         });
    
    //don't really have a use for this, but processor node won't run without being connected to an output
    MediaStreamAudioDestinationNode dest = audioContext.createMediaStreamDestination();
    
    mediaStreamSource.connectNode(lowPass);
    lowPass.connectNode(processor);
    processor.connectNode(dest);
    
    stage.juggler.tween(titleText, 1)
      ..animate.alpha.to(0)
      ..onComplete = () => titleText.removeFromParent();
    
  });

}

int noteFromPitch( frequency ) {
  if(frequency==0) return 0;
  var noteNum = 12 * (log( frequency / 440 )/log(2) );
  return noteNum.round() + 69;
}

num frequencyFromNoteNumber( note ) {
  return 440 * pow(2,(note-69)/12);
}

num centsOffFromPitch( frequency, note ) {
  return ( 1200 * log( frequency / frequencyFromNoteNumber( note ))/log(2) );
}

void tune(buf, sampleRate) {
  var lower = sampleRate~/2093;  // 2093 C7
  var upper = sampleRate~/32.7032; // 32.7032 Hz C1
  var samples = buf.length - upper;
  var best_offset = -1;
  var best_correlation = 0;
  var rms = 0;
  
  if (buf.length < (samples + upper - lower))
    return;  // Not enough data

  for (var i=0;i<samples;i++) {
    var val = buf[i];
    rms += val*val;
  }
  rms = sqrt(rms/samples);

  for (var offset = lower; offset < upper; offset++) {
    var correlation = 0;

    for (var i=0; i<samples; i++) {
      correlation += (buf[i]-buf[i+offset]).abs();
    }
    correlation = 1 - (correlation/samples);
    //weight slightly against lower freq to avoid octave erros
    correlation = correlation * .9+(upper-offset)/(upper-lower)/185;
    if (correlation > best_correlation) {
      best_correlation = correlation;
      best_offset = offset;
    }
  }
  
  if (rms>.009 && best_correlation > 0.5) {
    confidence = best_correlation * rms * 10000;
    currentPitch = sampleRate/best_offset;
  } else if(hold++>30) {
    confidence = 0;
    currentPitch = 0;
    hold = 0;
    pitchRing.fillRange(0, 4, 0);
    noteRing.fillRange(0, 4, 0);
  }
  
  noteRing[iRing] = noteFromPitch(currentPitch);
    pitchRing[iRing] = currentPitch;
    iRing = (iRing + 1) % noteRing.length;
    
    var noteCounts = new Map(), iNote;
    for(var i=0; i<noteRing.length; i++) {
      iNote = noteRing[i];
      if(noteCounts.containsKey(iNote)) {
        noteCounts[iNote]['c']++;
        noteCounts[iNote]['p'] = (noteCounts[iNote]['p'] + pitchRing[i])/2;
      }
      else noteCounts[iNote] = {'c': 1, 'p': pitchRing[i]};
    }
    
    noteCounts.forEach((k,v) {
      if(v['c']>2) {
        currentNote = k;
        currentPitch = v['p'];
      }  
    });
    
    
    var needle = flight.getChildByName('needle');
    if (currentPitch==0) {
      //determine required fall angle (holy trig)
      double angle = asin((stage.contentRectangle.width/2+flight.width/4)/flight.pivotY);
      if(angle.isNaN) angle = PI/2;
      if(!falling) {
        var pos = flight.rotation<=0?-angle:angle;
        stage.juggler.addGroup([
            new Tween(flight, 1, TransitionFunction.easeOutBounce)
              ..animate.rotation.to(pos)
              ..onStart = (() => falling = true),
            new Tween(notes, 1, TransitionFunction.easeOutCircular)..animate.alpha.to(0),
            new Tween(needle, 1, TransitionFunction.easeOutCircular)..animate.alpha.to(0),
            new Tween(gauge, 1, TransitionFunction.easeOutCircular)..animate.alpha.to(0)]);
        stage.juggler.transition(flight.vr, 0, 1.5, TransitionFunction.easeOutCircular, (v) => flight.vr = v);
      }
      
    } else {
      falling = false;
      TextField curFreqText = stage.getChildByName('gauge').getChildByName('freqText');
      
      curFreqText.text = currentPitch.floor().toString()+' Hz';
    
      if(currentNote!=0) {
        var note = currentNote;
        var detune = centsOffFromPitch( currentPitch, note );    
        stage.juggler.addGroup([
                                new Tween(notes, 1, TransitionFunction.easeOutCircular)
                                  ..animate.x.to((note-24)*-noteGap+818) //C1 is note 24
                                  ..animate.alpha.to(.8), 
                                new Tween(gauge, 1, TransitionFunction.easeOutCircular)
                                  ..animate.alpha.to(.8)]);
        
        if(!falling) {
          var pos = 2*PI*(detune.abs()>60?60*detune.sign:detune)/360;
          flight.vr = 23-pos/3;
          curFreqText
            ..textColor = (pos.abs()<.1)?0xFFAAEEAA:0xFFDDDDFF
            ..defaultTextFormat.underline = (pos.abs()<.1)?true:false;
          
          stage.juggler.removeTweens(flight);
          stage.juggler.addGroup([new Tween(flight, .5, TransitionFunction.easeOutBack)
                            ..animate.rotation.to(pos),
                            new Tween(needle, .5)..animate.alpha.to(1-pos/(PI/2))]);
        }            
        
      }
      
    }
  
}
