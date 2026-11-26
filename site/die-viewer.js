(() => {
  const stage = document.querySelector("#die-stage");
  const model = document.querySelector("#die-model");
  const gap = document.querySelector("#die-gap");
  const layerOptions = [...document.querySelectorAll("[data-layer]")];
  const planes = new Map(
    [...model.querySelectorAll("[data-plane]")].map((image) => [image.dataset.plane, image])
  );
  const initial = { pitch: 38, yaw: -20, zoom: 1, gap: 8 };
  let view = { ...initial };
  let drag = null;

  function draw() {
    model.style.setProperty("--pitch", `${view.pitch}deg`);
    model.style.setProperty("--yaw", `${view.yaw}deg`);
    model.style.setProperty("--zoom", view.zoom);
    model.style.setProperty("--gap", `${view.gap * Math.min(1, stage.clientWidth / 650)}px`);
  }

  function rotate(pitch, yaw) {
    view.pitch = Math.min(72, Math.max(-62, view.pitch + pitch));
    view.yaw = (view.yaw + yaw) % 360;
    draw();
  }

  function zoom(factor) {
    view.zoom = Math.min(3, Math.max(0.5, view.zoom * factor));
    draw();
  }

  function reset() {
    view = { ...initial };
    gap.value = view.gap;
    draw();
  }

  stage.addEventListener("pointerdown", (event) => {
    if (event.button !== 0 || drag || event.target.closest("a")) return;
    stage.focus({ preventScroll: true });
    stage.setPointerCapture(event.pointerId);
    drag = { id: event.pointerId, x: event.clientX, y: event.clientY };
  });
  stage.addEventListener("pointermove", (event) => {
    if (event.pointerId !== drag?.id) return;
    rotate((drag.y - event.clientY) * 0.42, (event.clientX - drag.x) * 0.45);
    drag.x = event.clientX;
    drag.y = event.clientY;
  });
  stage.addEventListener("lostpointercapture", (event) => {
    if (event.pointerId === drag?.id) drag = null;
  });
  stage.addEventListener("wheel", (event) => {
    if (document.activeElement !== stage || event.ctrlKey) return;
    event.preventDefault();
    zoom(event.deltaY < 0 ? 1.12 : 1 / 1.12);
  }, { passive: false });
  stage.addEventListener("keydown", (event) => {
    const actions = {
      ArrowLeft: () => rotate(0, -8), ArrowRight: () => rotate(0, 8),
      ArrowUp: () => rotate(8, 0), ArrowDown: () => rotate(-8, 0),
      "+": () => zoom(1.2), "-": () => zoom(1 / 1.2), "0": reset,
    };
    if (!Object.hasOwn(actions, event.key) || event.target !== stage) return;
    event.preventDefault();
    actions[event.key]();
  });
  document.querySelector("#die-out").addEventListener("click", () => zoom(1 / 1.2));
  document.querySelector("#die-in").addEventListener("click", () => zoom(1.2));
  document.querySelector("#die-reset").addEventListener("click", reset);
  document.querySelector("#die-top").addEventListener("click", () => {
    Object.assign(view, { yaw: 0, pitch: 0, zoom: 1 });
    draw();
  });
  gap.addEventListener("input", () => {
    view.gap = Number(gap.value);
    draw();
  });
  for (const option of layerOptions) {
    const plane = planes.get(option.dataset.layer);
    const fail = () => { document.querySelector("#die-error").hidden = false; };
    plane.addEventListener("error", fail);
    if (plane.complete && !plane.naturalWidth) fail();
    option.addEventListener("change", () => { plane.hidden = !option.checked; });
  }
  new ResizeObserver(draw).observe(stage);
  draw();
})();
