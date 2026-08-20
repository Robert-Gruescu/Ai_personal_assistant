// Conținutul site-ului de prezentare ASIS.
// Textele se editează aici — componentele nu trebuie atinse.

export const stats = [
  { value: "2", label: "moduri: vorbit sau scris" },
  { value: "1", label: "buton de apăsat" },
  { value: "0", label: "servere unde să-ți plece datele" },
  { value: "RO", label: "vorbește românește" },
];

export const features = [
  {
    icon: "mic",
    title: "Spui, se face",
    text: "Apeși microfonul și vorbești normal, ca unui om. Fără comenzi de învățat pe de rost și fără să scrii nimic când ai mâinile ocupate.",
    tag: "Doar vorbești",
  },
  {
    icon: "check",
    title: "Nu mai uiți nimic",
    text: "„Mâine la 14 vreau să sun la dentist” e de ajuns. Îți sună telefonul cu zece minute înainte, chiar dacă între timp l-ai repornit.",
    tag: "Te anunță la timp",
  },
  {
    icon: "cart",
    title: "Lista de cumpărături",
    text: "Îi spui zece produse dintr-o suflare și le pune pe toate. Iar când lista se face mare, îți spune singur la ce magazin ieși mai ieftin.",
    tag: "Îți compară prețurile",
  },
  {
    icon: "mail",
    title: "Îți citește emailurile",
    text: "Îți spune cine ți-a scris și ce vrea, pe scurt, în timp ce tu faci altceva. Poate să caute și un email anume, după nume sau după subiect.",
    tag: "Pe scurt, cu voce",
  },
  {
    icon: "video",
    title: "Întâlniri puse la punct",
    text: "Dintr-o propoziție iese o întâlnire adevărată: apare în calendar, are link de Google Meet care chiar funcționează, iar invitatul primește invitația.",
    tag: "Gata în zece secunde",
  },
  {
    icon: "tag",
    title: "Ofertele săptămânii",
    text: "Îți arată ce s-a ieftinit și pune primele produsele care sunt deja pe lista ta. Restul rămân mai jos, dacă tot te uiți.",
    tag: "Ce e la reducere",
  },
  {
    icon: "brain",
    title: "Ține minte ce contează",
    text: "„Ține minte că beau cafea fără zahăr.” De atunci știe. Reține doar ce îi ceri tu, iar dacă te răzgândești, uită la comandă.",
    tag: "Rămâne pe telefon",
  },
  {
    icon: "grid",
    title: "Direct pe ecranul telefonului",
    text: "Un widget cu ce ai de făcut azi și ce ai de cumpărat. O atingere și se deschide fix lista pe care voiai s-o vezi.",
    tag: "Fără să deschizi aplicația",
  },
];

export const flow = [
  {
    step: "01",
    title: "Vorbești",
    text: "Apeși o dată pe microfon și spui ce ai nevoie, cu cuvintele tale. Dacă preferi să scrii, ai și un mod de chat.",
  },
  {
    step: "02",
    title: "Își aduce aminte unde ai rămas",
    text: "Se uită la ce ai deja pe liste și la lucrurile pe care i le-ai spus despre tine, ca să nu te mai întrebe ce știe deja.",
  },
  {
    step: "03",
    title: "Înțelege ce vrei",
    text: "Face diferența între o comandă clară și o vorbă aruncată în treacăt. Pe prima o execută, la a doua te întreabă întâi.",
  },
  {
    step: "04",
    title: "Face treaba",
    text: "Scrie emailul, pune produsul pe listă, programează întâlnirea, caută prețul. Concret, nu doar îți explică cum ai putea face tu.",
  },
  {
    step: "05",
    title: "Îți spune ce a făcut",
    text: "Îți răspunde cu voce, scurt și pe înțeles, iar conversația rămâne salvată dacă vrei s-o reiei mai târziu.",
  },
];

export const conversation = [
  { from: "user", text: "Adaugă lapte, ouă și cafea pe listă" },
  {
    from: "asis",
    text: "Am adăugat 3 produse: lapte, ouă, cafea. Mai ai nevoie de altceva?",
  },
  { from: "user", text: "Ce reduceri sunt la produsele de pe lista mea?" },
  {
    from: "asis",
    text: "Ai cafea la 24,90 lei, redusă de la 32,50. Oferta ține până duminică.",
  },
  { from: "user", text: "Ține minte că beau cafea fără zahăr" },
  { from: "asis", text: "Am reținut. O să țin cont data viitoare." },
];

// Exemple de fraze spuse cu voce tare, grupate pe felul lor.
export const phrases = [
  {
    group: "Pentru ce ai de făcut",
    lines: [
      "Adaugă task: sun la service marți dimineață",
      "Ce am de făcut azi?",
      "Am terminat cu factura de curent",
    ],
  },
  {
    group: "Pentru cumpărături",
    lines: [
      "Pune pâine, roșii și detergent pe listă",
      "Ce am pe lista de cumpărături?",
      "Ce reduceri sunt săptămâna asta?",
    ],
  },
  {
    group: "Pentru email și întâlniri",
    lines: [
      "Citește-mi ultimul email",
      "Fă-mi un rezumat la ce mi-a scris Ana",
      "Programează o întâlnire cu ion@exemplu.ro mâine la 10",
    ],
  },
  {
    group: "Pentru lucruri despre tine",
    lines: [
      "Ține minte că sunt alergic la arahide",
      "Ce știi despre mine?",
      "Uită ce ți-am spus despre mașină",
    ],
  },
];

export const layers = [
  {
    name: "Ce vezi",
    color: "from-violet-500/20 to-violet-500/5",
    items: [
      "Un ecran cu un singur buton, pentru când vrei să vorbești",
      "Un mod de chat clasic, pentru când e gălăgie sau ești în ședință",
      "Liste de task-uri și de cumpărături, la o atingere distanță",
      "Conversațiile vechi, salvate, dacă vrei să te întorci la ele",
    ],
  },
  {
    name: "Ce înțelege",
    color: "from-indigo-500/20 to-indigo-500/5",
    items: [
      "Vorbire liberă în română, fără cuvinte-cheie de memorat",
      "Diferența dintre „adaugă lapte” și „cred că mi-a cam terminat laptele”",
      "Datele spuse omenește: mâine, poimâine, marți la 14",
      "Contextul: știe ce ai pe liste, deci nu te mai întreabă",
    ],
  },
  {
    name: "Ce face",
    color: "from-sky-500/20 to-sky-500/5",
    items: [
      "Scrie și trimite emailuri de pe adresa ta",
      "Creează întâlniri reale, cu link de Meet și invitație trimisă",
      "Caută prețuri și oferte și îți dă răspunsul, nu zece linkuri",
      "Îți programează memento-uri care sună când trebuie",
    ],
  },
  {
    name: "Unde stau datele",
    color: "from-emerald-500/20 to-emerald-500/5",
    items: [
      "Listele, conversațiile și ce ține minte — pe telefonul tău",
      "Nu există un server al aplicației unde să ajungă",
      "Emailul și calendarul se ating doar când ceri tu asta",
      "Ștergi tot dintr-un singur loc, în setări",
    ],
  },
];

export const stack = [
  { name: "Merge pe Android", role: "Telefonul pe care îl ai deja" },
  { name: "Înțelege româna", role: "Vorbire naturală, nu comenzi rigide" },
  { name: "Vorbește înapoi", role: "Răspunsuri citite cu voce tare" },
  { name: "Datele local", role: "Listele și memoria rămân pe telefon" },
  { name: "Gmail și Calendar", role: "Cu contul tău, când îl conectezi" },
  { name: "Google Meet", role: "Linkuri de întâlnire adevărate" },
  { name: "Memento-uri", role: "Notificări care sună la fix" },
  { name: "Widget", role: "Ziua ta, direct pe ecranul principal" },
];

export const privacy = [
  {
    title: "Rămân pe telefon",
    text: "Listele, conversațiile și lucrurile pe care le ține minte stau în telefonul tău. Aplicația nu are un server al ei unde să le trimită.",
  },
  {
    title: "Tu decizi ce conectezi",
    text: "Emailul și calendarul se folosesc doar dacă îți conectezi contul Google, o singură dată și cu permisiuni pe care le vezi.",
  },
  {
    title: "Uită la comandă",
    text: "Reține doar ce îi spui explicit să rețină. Îi ceri să uite ceva și dispare. Iar dacă vrei, ștergi tot dintr-un singur buton.",
  },
];
