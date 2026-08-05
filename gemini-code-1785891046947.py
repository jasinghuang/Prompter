svg_content = """<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">
  <defs>
    <linearGradient id="bgGradient" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#6B52C4"/>
      <stop offset="100%" stop-color="#3A297D"/>
    </linearGradient>
  </defs>
  
  <!-- App Icon Background -->
  <rect x="32" y="32" width="448" height="448" rx="104" fill="url(#bgGradient)" />

  <!-- Speech Bubble Outline -->
  <path d="M 140 156 H 372 V 316 H 220 L 140 396 Z" 
        fill="none" 
        stroke="white" 
        stroke-width="32" 
        stroke-linejoin="round" />

  <!-- Text Lines -->
  <path d="M 196 212 H 316 M 196 260 H 260" 
        fill="none" 
        stroke="white" 
        stroke-width="28" 
        stroke-linecap="round" />
</svg>"""

with open("speech_beam_logo.svg", "w") as f:
    f.write(svg_content)

print("SVG generation complete.")