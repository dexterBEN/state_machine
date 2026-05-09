enum WashState { idle, fill, wash, rinse, spin, done}

WashState parseWashState(String s) {
  switch(s.toUpperCase()) {
    case 'IDLE': return WashState.idle;
    case 'FILL': return WashState.fill;
    case 'WASH': return WashState.wash;
    case 'RINSE': return WashState.rinse;
    case 'SPIN': return WashState.spin;
    case 'DONE': return WashState.done;
    default: return WashState.idle;
  }
}