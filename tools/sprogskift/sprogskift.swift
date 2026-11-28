import AVFoundation
// Brug: mix <mode> <marked.txt> <outdir>   mode: sara | switch:<voiceid> | ssml
let args = CommandLine.arguments
let mode = args[1]; let lines = try! String(contentsOfFile: args[2], encoding: .utf8).split(separator: "\n").map(String.init)
let outDir = URL(fileURLWithPath: args[3]); try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let sara = AVSpeechSynthesisVoice(identifier: "com.apple.voice.enhanced.da-DK.Sara")!
let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 22050, channels: 1, interleaved: false)!
func segments(_ line: String) -> [(String, Bool)] {
  var out: [(String, Bool)] = []; var cur = ""; var eng = false
  for ch in line { if ch == "{" || ch == "}" { if !cur.isEmpty { out.append((cur, eng)) }; cur = ""; eng = ch == "{" } else { cur.append(ch) } }
  if !cur.isEmpty { out.append((cur, eng)) }
  // Tegn alene (". ", ", ") hænges på stykket før, så de ikke læses som "punktum".
  var merged: [(String, Bool)] = []
  for (t, e) in out {
    let letters = t.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    if !letters, !merged.isEmpty { merged[merged.count - 1].0 += t } else { merged.append((t, e)) }
  }
  return merged
}
func render(_ u: AVSpeechUtterance) -> [AVAudioPCMBuffer] {
  let s = AVSpeechSynthesizer(); var bufs: [AVAudioPCMBuffer] = []; var done = false
  s.write(u) { b in
    guard let p = b as? AVAudioPCMBuffer else { return }
    if p.frameLength == 0 { done = true; return }
    let conv = AVAudioConverter(from: p.format, to: fmt)!
    let cap = AVAudioFrameCount(Double(p.frameLength) * 22050 / p.format.sampleRate) + 64
    let o = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: cap)!
    var given = false
    _ = conv.convert(to: o, error: nil) { _, st in if given { st.pointee = .endOfStream; return nil }; given = true; st.pointee = .haveData; return p }
    bufs.append(o)
  }
  let end = Date().addingTimeInterval(30)
  while !done, Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
  return bufs
}
func utt(_ t: String, _ v: AVSpeechSynthesisVoice) -> AVSpeechUtterance { let u = AVSpeechUtterance(string: t); u.voice = v; u.rate = AVSpeechUtteranceDefaultSpeechRate; return u }
for (i, line) in lines.enumerated() {
  var bufs: [AVAudioPCMBuffer] = []
  let plain = line.replacingOccurrences(of: "{", with: "").replacingOccurrences(of: "}", with: "")
  if mode == "sara" { bufs = render(utt(plain, sara)) }
  else if mode == "ssml" {
    var x = "<speak>"; for (t, e) in segments(line) { x += e ? "<lang xml:lang=\"en-US\">\(t)</lang>" : t }; x += "</speak>"
    let u = AVSpeechUtterance(ssmlRepresentation: x)!; u.voice = sara; bufs = render(u)
  } else {
    let en = AVSpeechSynthesisVoice(identifier: String(mode.dropFirst(7)))!
    for (t, e) in segments(line) where !t.trimmingCharacters(in: .whitespaces).isEmpty || true {
      let trimmed = t.trimmingCharacters(in: .whitespaces); if trimmed.isEmpty { continue }
      bufs += render(utt(trimmed, e ? en : sara))
    }
  }
  let url = outDir.appendingPathComponent(String(format: "%02d.wav", i))
  let f = try! AVAudioFile(forWriting: url, settings: fmt.settings, commonFormat: .pcmFormatFloat32, interleaved: false)
  for b in bufs { try! f.write(from: b) }
}
print("ok", lines.count)
