const overlay = document.querySelector("#overlay");
const select = document.querySelector("#macro");
const details = document.querySelector("#details");
const filters = [...document.querySelectorAll("[data-group]")];
const initialDetails = details.querySelector("p").textContent;
const labels = { activation: "Aktivasi", weights: "Bobot", requant: "Requant", firmware: "Firmware" };
const number = new Intl.NumberFormat("id-ID", { maximumFractionDigits: 3 });
let group = "all";
let selected = "";

function startViewer(placement) {
  const [dieWidth, dieHeight] = placement.die_um;
  // The KLayout export targets the die plus a 40 µm margin on each side.
  const scale = Math.min(1440 / (dieWidth + 80), 1008 / (dieHeight + 80));
  const left = (1440 - dieWidth * scale) / 2;
  const top = (1008 - dieHeight * scale) / 2;
  const macros = placement.sram.map((macro) => {
    const [x, y, right, upper] = macro.bbox_um;
    const rect = document.createElementNS("http://www.w3.org/2000/svg", "rect");
    rect.setAttribute("x", left + x * scale);
    rect.setAttribute("y", top + (dieHeight - upper) * scale);
    rect.setAttribute("width", (right - x) * scale);
    rect.setAttribute("height", (upper - y) * scale);
    rect.classList.add("macro");
    overlay.append(rect);
    return { ...macro, rect, group: macro.name.split("_")[0] };
  });

  function showSelected() {
    for (const macro of macros) {
      const matches = group === "all" || macro.group === group;
      macro.rect.classList.toggle("is-dim", !matches);
      macro.rect.classList.toggle("is-active", matches && group !== "all");
      macro.rect.classList.toggle("is-selected", macro.name === selected);
    }
    const macro = macros.find((item) => item.name === selected);
    if (!macro) {
      const paragraph = document.createElement("p");
      paragraph.textContent = group === "all"
        ? initialDetails
        : `${labels[group]} · ${macros.filter((item) => item.group === group).length} makro. Pilih satu makro untuk melihat detailnya.`;
      details.replaceChildren(paragraph);
      return;
    }
    const [x, y, right, upper] = macro.bbox_um;
    const data = [
      ["Makro IHP", macro.master],
      ["Sudut kiri bawah (x, y)", `${number.format(x)} / ${number.format(y)} µm`],
      ["Ukuran", `${number.format(right - x)} × ${number.format(upper - y)} µm`],
      ["Orientasi", macro.orientation],
    ];
    const list = document.createElement("dl");
    for (const [label, value] of data) {
      const term = document.createElement("dt");
      const definition = document.createElement("dd");
      term.textContent = label;
      definition.textContent = value;
      list.append(term, definition);
    }
    details.replaceChildren(list);
  }

  function showGroup() {
    select.replaceChildren(new Option("Pilih makro", ""));
    for (const macro of macros) {
      if (group === "all" || macro.group === group) select.add(new Option(macro.name, macro.name));
    }
    select.value = selected;
    for (const button of filters) button.setAttribute("aria-pressed", String(button.dataset.group === group));
    showSelected();
  }

  for (const macro of macros) {
    macro.rect.addEventListener("click", () => {
      selected = macro.name;
      select.value = selected;
      showSelected();
    });
  }
  for (const button of filters) {
    button.disabled = false;
    button.addEventListener("click", () => {
      group = button.dataset.group;
      selected = "";
      showGroup();
    });
  }
  select.disabled = false;
  select.addEventListener("change", () => {
    selected = select.value;
    showSelected();
  });
  overlay.removeAttribute("hidden");
  showGroup();
}

fetch("assets/placement.json")
  .then((response) => {
    if (!response.ok) throw new Error(`Placement HTTP ${response.status}`);
    return response.json();
  })
  .then(startViewer)
  .catch(() => { document.querySelector("#viewer-error").hidden = false; });
