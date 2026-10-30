/// Cold-start seed list for the news feed: high-frequency Spanish press
/// idioms (locuciones) and the verb–noun collocations a Russian speaker
/// typically calques. While the user has collected almost nothing of their
/// own, the feed composer introduces at most two of these a day.
///
/// Why a small hand-verified list instead of asking the model: a wrong gloss
/// or a non-existent idiom would TEACH AN ERROR. Every entry was checked
/// (2026-09-26) against the DLE (dle.rae.es) or — where the DLE is silent —
/// the DPD, FundéuRAE or the CVC, and against a news-headline search showing
/// current use in the Spanish press. The source is noted above each entry.
/// Two corrections to common press usage are deliberate: «contra reloj»
/// (the DPD rejects «a contrarreloj») and «hacer agua» (the form the DPD and
/// FundéuRAE recommend over «hacer aguas», whose first meaning is 'orinar').
///
/// Field conventions the composer and the feed validator rely on:
/// * [SeedExpression.searchForm] — the words that must appear in running
///   text, in citation order. A leading verb is an infinitive — with the
///   enclitic «-se» when the locution is pronominal («lavarse las manos» →
///   «se lava las manos») — and is inflected in text, often irregularly
///   (dar → dio, poner → puso, hacer → hizo, tener → tiene). Everything after
///   the verb is fixed, although a direct object may stand between the verb
///   and the rest («pone una propuesta sobre la mesa»). When the dictionary
///   lists the locution with a variable verb (estar / poner / quedar…), the
///   verb is left out: «en tela de juicio», «en punto muerto».
/// * [SeedExpression.register] mirrors the DLE usage mark for the sense
///   glossed: 'coloquial' = «coloq.», 'neutral' = unmarked. Several
///   'coloquial' ones (tirar la toalla, dar marcha atrás, hacer hincapié) are
///   nonetheless routine in Spanish news prose. None is marked «cult.».
/// * [SeedExpression.region] is '' (pan-Hispanic) unless the DLE marks the
///   entry «Esp.» → 'es-ES'.
/// * Order is pedagogical: the composer takes the first entries not yet in
///   the learner's items, so the most frequent, neutral and calque-prone
///   expressions come first, alternating idioms and collocations.
library;

class SeedExpression {
  /// Citation form with its usual frame, as it is taught:
  /// «dar luz verde (a algo)», «hacer hincapié en (algo)».
  final String canonical;

  /// The words that must appear in the text (see the library comment).
  /// Unique across the list — it is the learning item's key.
  final String searchForm;

  /// Closest real Russian equivalent (idiom if one exists), otherwise a
  /// precise description. May carry a short warning about a trap form.
  final String glossRu;

  /// 'idiom' | 'collocation'.
  final String kind;

  /// 'neutral' | 'coloquial' | 'culto'.
  final String register;

  /// '' (pan-Hispanic) | 'es-ES'.
  final String region;

  /// One short original sentence in news style (es-ES norms), written for
  /// this list — not copied from any article.
  final String example;

  const SeedExpression({
    required this.canonical,
    required this.searchForm,
    required this.glossRu,
    required this.kind,
    this.register = 'neutral',
    this.region = '',
    required this.example,
  });
}

const kSeedExpressionsEs = <SeedExpression>[
  // DLE s.v. luz: «luz verde» 'camino o procedimiento abierto… para el
  // logro de un asunto'.
  SeedExpression(
    canonical: 'dar luz verde (a algo)',
    searchForm: 'dar luz verde',
    glossRu: 'дать зелёный свет, одобрить',
    kind: 'idiom',
    example: 'El Ayuntamiento ha dado luz verde al nuevo carril bici del '
        'centro.',
  ),
  // DLE s.v. cabo: «llevar a cabo algo» 'ejecutarlo, concluirlo'. Russian
  // «проводить (операцию, реформу)» has no verb-for-verb match in Spanish.
  SeedExpression(
    canonical: 'llevar a cabo (algo)',
    searchForm: 'llevar a cabo',
    glossRu: 'осуществить, провести (операцию, реформу)',
    kind: 'collocation',
    example: 'La Guardia Civil llevó a cabo ayer una veintena de registros '
        'en tres provincias.',
  ),
  // Not in the DLE (it lists the older «estar sobre el tapete»); verified by
  // current use, e.g. RTVE 3.8.2026 «Trump pone sobre la mesa una propuesta…».
  SeedExpression(
    canonical: 'poner (algo) sobre la mesa',
    searchForm: 'poner sobre la mesa',
    glossRu: 'выдвинуть (предложение), вынести (вопрос) на обсуждение',
    kind: 'idiom',
    example: 'Los sindicatos han puesto sobre la mesa una propuesta de subida '
        'salarial para los próximos dos años.',
  ),
  // DLE s.v. medida, 6: «Tomar, adoptar medidas». Calque: *aceptar medidas.
  SeedExpression(
    canonical: 'tomar medidas',
    searchForm: 'tomar medidas',
    glossRu: 'принять меры',
    kind: 'collocation',
    example: 'Los vecinos piden al Ayuntamiento que tome medidas contra el '
        'ruido nocturno.',
  ),
  // DLE s.v. factura: «pasar factura», 2 'traer malas consecuencias'.
  SeedExpression(
    canonical: 'pasar factura (a alguien)',
    searchForm: 'pasar factura',
    glossRu: 'аукнуться, негативно сказаться (на ком-л.)',
    kind: 'idiom',
    example: 'La sequía empieza a pasar factura a los agricultores del sur.',
  ),
  // DLE s.v. frente: «hacer frente» 'plantar cara'.
  SeedExpression(
    canonical: 'hacer frente a (algo)',
    searchForm: 'hacer frente',
    // Not «справиться с кризисом»: the outcome is open (verified 2026-09-26).
    glossRu: 'противостоять, бороться с (кризисом, угрозой); справляться с '
        '(расходами, платежами)',
    kind: 'collocation',
    example: 'Muchas familias no pueden hacer frente a la subida de los '
        'alquileres.',
  ),
  // DLE s.v. punto: «punto de mira», 2 'objeto y centro de atención e
  // interés'.
  SeedExpression(
    canonical: 'estar en el punto de mira (de alguien)',
    searchForm: 'en el punto de mira',
    glossRu: 'быть под прицелом (критики, проверок)',
    kind: 'idiom',
    example: 'Las eléctricas están en el punto de mira por la subida de la '
        'factura de la luz.',
  ),
  // DLE s.v. decisión, 1 'resolución que se toma'; s.v. tomar, 27. Calque:
  // *aceptar una decisión (= согласиться с чужим решением).
  SeedExpression(
    canonical: 'tomar una decisión',
    searchForm: 'tomar una decisión',
    glossRu: 'принять решение',
    kind: 'collocation',
    example: 'El comité de empresa tomará una decisión sobre la huelga la '
        'próxima semana.',
  ),
  // DLE s.v. leña: «echar leña al fuego» 'poner medios para acrecentar un
  // mal'.
  SeedExpression(
    canonical: 'echar leña al fuego',
    searchForm: 'echar leña al fuego',
    glossRu: 'подливать масла в огонь',
    kind: 'idiom',
    example: 'Las declaraciones del portavoz no han hecho más que echar leña '
        'al fuego.',
  ),
  // DLE s.v. marcha: «poner en marcha», 2 'hacer que un proyecto comience a
  // realizarse'.
  SeedExpression(
    canonical: 'poner en marcha (algo)',
    searchForm: 'poner en marcha',
    glossRu: 'запустить, ввести в действие',
    kind: 'collocation',
    example: 'La Comunidad pondrá en marcha un plan de empleo para menores de '
        '30 años.',
  ),
  // DLE s.v. marcha: «dar marcha atrás», coloq. 'desistir de un empeño'.
  SeedExpression(
    canonical: 'dar marcha atrás',
    searchForm: 'dar marcha atrás',
    glossRu: 'дать задний ход, отказаться от своего решения',
    kind: 'idiom',
    register: 'coloquial',
    example: 'Tras las críticas, el Gobierno ha dado marcha atrás y retirará '
        'la nueva tasa.',
  ),
  // DLE s.v. sacar: «sacar adelante», 2 'llevar un asunto a feliz término'.
  SeedExpression(
    canonical: 'sacar adelante (algo)',
    searchForm: 'sacar adelante',
    glossRu: 'довести до успешного конца, добиться принятия (закона, '
        'бюджета)',
    kind: 'collocation',
    example: 'El Ejecutivo necesita el apoyo de sus socios para sacar adelante '
        'los presupuestos.',
  ),
  // DLE s.v. tela: «en tela de juicio» 'en duda. Estar, poner, quedar algo
  // en tela de juicio'.
  SeedExpression(
    canonical: 'poner (algo) en tela de juicio',
    searchForm: 'en tela de juicio',
    glossRu: 'поставить под сомнение',
    kind: 'idiom',
    example: 'Un informe independiente pone en tela de juicio la eficacia de '
        'las ayudas al alquiler.',
  ),
  // DLE s.v. paso: «dar un paso, o un paso adelante» 'realizar un progreso
  // perceptible'. Calque: *hacer un paso.
  SeedExpression(
    canonical: 'dar un paso (adelante)',
    searchForm: 'dar un paso',
    glossRu: 'сделать шаг (вперёд), продвинуться',
    kind: 'collocation',
    example: 'Las dos partes han dado un paso decisivo hacia un acuerdo.',
  ),
  // DLE s.v. fila: «cerrar filas» 'unirse estrechamente para hacer frente a
  // algo'.
  SeedExpression(
    canonical: 'cerrar filas (en torno a alguien)',
    searchForm: 'cerrar filas',
    glossRu: 'сомкнуть ряды, сплотиться (вокруг кого-л.)',
    kind: 'idiom',
    example: 'El partido ha cerrado filas en torno a su candidata tras la '
        'polémica.',
  ),
  // DLE s.v. cometer, 1 'caer o incurrir en una culpa, yerro…'. Calque:
  // *hacer un error.
  SeedExpression(
    canonical: 'cometer un error',
    searchForm: 'cometer un error',
    glossRu: 'совершить ошибку',
    kind: 'collocation',
    example: 'El consejero admitió que cometió un error al anunciar la medida '
        'sin consultar a los sindicatos.',
  ),
  // DLE s.v. luz: «sacar a luz, o a la luz» 'descubrir… lo que estaba
  // oculto'.
  SeedExpression(
    canonical: 'sacar (algo) a la luz',
    searchForm: 'sacar a la luz',
    glossRu: 'вытащить на свет, предать огласке',
    kind: 'idiom',
    example: 'Una investigación periodística ha sacado a la luz '
        'irregularidades en varios contratos públicos.',
  ),
  // DLE s.v. vigor, 3 'fuerza de obligar en las leyes'. Calque: *entrar en
  // fuerza.
  SeedExpression(
    canonical: 'entrar en vigor',
    searchForm: 'entrar en vigor',
    glossRu: 'вступить в силу',
    kind: 'collocation',
    example: 'La nueva ordenanza de terrazas entrará en vigor el 1 de enero.',
  ),
  // DLE s.v. cara: «dar la cara» 'responder de los propios actos y afrontar
  // sus consecuencias'.
  SeedExpression(
    canonical: 'dar la cara',
    searchForm: 'dar la cara',
    glossRu: 'отвечать за свои поступки, не прятаться от ответственности',
    kind: 'idiom',
    example: 'Los vecinos exigen que la empresa dé la cara y explique los '
        'cortes de agua.',
  ),
  // DLE s.v. hincapié: «hacer alguien hincapié», coloq. 'insistir en algo'.
  // Calque of «делать акцент»: *hacer acento (correct: poner el acento en).
  SeedExpression(
    canonical: 'hacer hincapié en (algo)',
    searchForm: 'hacer hincapié',
    glossRu: 'делать упор на (чём-л.), особо подчёркивать',
    kind: 'collocation',
    register: 'coloquial',
    example: 'La directora del hospital hizo hincapié en la necesidad de '
        'reforzar la plantilla.',
  ),
  // DLE s.v. paso: «salir al paso de algo» 'darse por enterado de ello e
  // impugnar su veracidad o su fundamento'.
  SeedExpression(
    canonical: 'salir al paso (de algo)',
    searchForm: 'salir al paso',
    glossRu: 'публично опровергнуть, ответить на (слухи, критику)',
    kind: 'idiom',
    example: 'El club ha salido al paso de los rumores sobre la venta del '
        'estadio.',
  ),
  // DLE s.v. sacar, 6 (sin. deducir, inferir, concluir). Calque: *hacer
  // conclusiones.
  SeedExpression(
    canonical: 'sacar conclusiones',
    searchForm: 'sacar conclusiones',
    glossRu: 'делать выводы',
    kind: 'collocation',
    example: 'Los técnicos piden no sacar conclusiones precipitadas antes de '
        'conocer el informe.',
  ),
  // DLE s.v. cuerda: «en la cuerda floja» 'en situación inestable,
  // conflictiva o peligrosa'.
  SeedExpression(
    canonical: 'estar en la cuerda floja',
    searchForm: 'en la cuerda floja',
    glossRu: 'быть в шатком положении, висеть на волоске',
    kind: 'idiom',
    example: 'Tras cinco derrotas seguidas, el entrenador está en la cuerda '
        'floja.',
  ),
  // DLE s.v. prestar, 4: «Prestar atención». Calque: *dar atención.
  SeedExpression(
    canonical: 'prestar atención (a algo)',
    searchForm: 'prestar atención',
    glossRu: 'уделять внимание, обращать внимание (на что-л.)',
    kind: 'collocation',
    example: 'Los médicos piden prestar atención a los primeros síntomas del '
        'golpe de calor.',
  ),
  // DLE s.v. mano: «lavarse alguien las manos» 'desentenderse de un
  // negocio en que hay inconvenientes'.
  SeedExpression(
    canonical: 'lavarse las manos',
    searchForm: 'lavarse las manos',
    glossRu: 'умыть руки',
    kind: 'idiom',
    example: 'La empresa se lava las manos y atribuye el retraso a sus '
        'proveedores.',
  ),
  // DLE s.v. marco, 5: «En el marco de la Constitución». Calque of
  // «в рамках»: *en los marcos de (Spanish uses the singular).
  SeedExpression(
    canonical: 'en el marco de (algo)',
    searchForm: 'en el marco de',
    glossRu: 'в рамках (чего-л.)',
    kind: 'collocation',
    example: 'Los dos ministros se reunieron en el marco de la cumbre europea '
        'de Bruselas.',
  ),
  // Not in the DLE; CVC «Martes neológico»: lexicalised in the 1980s,
  // frequent in political and sports journalism (recorded in the DEA).
  // https://blogscvc.cervantes.es/martes-neologico/mover-ficha/
  SeedExpression(
    canonical: 'mover ficha',
    searchForm: 'mover ficha',
    glossRu: 'сделать (свой) ход, предпринять шаг',
    kind: 'idiom',
    example: 'Tras semanas de silencio, la oposición ha movido ficha y ha '
        'registrado su propia propuesta.',
  ),
  // DLE s.v. lugar: «tener lugar algo» 'ocurrir, suceder, efectuarse'.
  // Anglicism to avoid: *tomar lugar (take place).
  SeedExpression(
    canonical: 'tener lugar',
    searchForm: 'tener lugar',
    glossRu: 'состояться, произойти',
    kind: 'collocation',
    example: 'La manifestación tendrá lugar el sábado a mediodía en el centro '
        'de la ciudad.',
  ),
  // DPD s.v. contrarreloj, 2: «contra reloj» 'con suma urgencia o con un
  // plazo perentorio'; «No es correcto anteponer… la preposición a:
  // ⊗a contrarreloj». Frequent in the press both ways, so taught explicitly.
  SeedExpression(
    canonical: '(trabajar, negociar) contra reloj',
    searchForm: 'contra reloj',
    // Not «в пожарном порядке» — that is hasty and slapdash (Ushakov).
    glossRu: 'наперегонки со временем, в режиме цейтнота, когда каждая '
        'минута на счету (без предлога «a»)',
    kind: 'idiom',
    example: 'Los equipos de rescate trabajan contra reloj para encontrar '
        'a los desaparecidos.',
  ),
  // DLE s.v. visto: «visto bueno», the formula of approval on documents;
  // «dar el visto bueno a» is its standard use in the press.
  SeedExpression(
    canonical: 'dar el visto bueno (a algo)',
    searchForm: 'dar el visto bueno',
    glossRu: 'одобрить, дать добро',
    kind: 'collocation',
    example: 'El pleno municipal ha dado el visto bueno a la reforma del '
        'mercado central.',
  ),
  // DLE s.v. toalla: «arrojar, o tirar, la toalla», 2, coloqs. 'darse por
  // vencido'.
  SeedExpression(
    canonical: 'tirar la toalla',
    searchForm: 'tirar la toalla',
    glossRu: 'сдаться, опустить руки',
    kind: 'idiom',
    register: 'coloquial',
    example: 'Pese a las encuestas, la candidata asegura que no piensa tirar '
        'la toalla.',
  ),
  // DLE s.v. manifiesto: «poner de manifiesto algo» 'mostrarlo, revelarlo'.
  SeedExpression(
    canonical: 'poner (algo) de manifiesto',
    searchForm: 'poner de manifiesto',
    glossRu: 'выявить, продемонстрировать, показать',
    kind: 'collocation',
    example: 'La tormenta ha puesto de manifiesto las carencias del '
        'alcantarillado.',
  ),
  // DLE s.v. brazo: «dar alguien su brazo a torcer» 'rendirse, desistir de
  // su dictamen o propósito. U. m. con neg.' — hence no «no» in searchForm.
  SeedExpression(
    canonical: 'no dar su brazo a torcer',
    searchForm: 'dar su brazo a torcer',
    glossRu: 'не уступать, стоять на своём',
    kind: 'idiom',
    example: 'Ni la patronal ni los sindicatos dan su brazo a torcer en la '
        'negociación del convenio.',
  ),
  // DLE s.v. lugar: «dar lugar a algo» 'ocasionar, motivar' (≠ tener lugar).
  SeedExpression(
    canonical: 'dar lugar a (algo)',
    searchForm: 'dar lugar a',
    glossRu: 'привести к (чему-л.), вызвать, повлечь',
    kind: 'collocation',
    example: 'El retraso de las obras ha dado lugar a numerosas quejas '
        'vecinales.',
  ),
  // DLE s.v. orden: «estar a la orden del día algo» 'estar de moda, en boga,
  // andar al uso'. False friend: «orden del día» alone is «повестка дня».
  SeedExpression(
    canonical: 'estar a la orden del día',
    searchForm: 'a la orden del día',
    glossRu: 'быть обычным делом, случаться сплошь и рядом '
        '(не «на повестке дня»)',
    kind: 'idiom',
    example: 'En esta carretera, los atascos en hora punta están a la orden '
        'del día.',
  ),
  // DLE s.v. razón: «dar la razón a alguien» 'concederle lo que dice'.
  // Trap: «dar razón» without the article means 'informar'.
  SeedExpression(
    canonical: 'dar la razón (a alguien)',
    searchForm: 'dar la razón',
    glossRu: 'признать чью-л. правоту',
    kind: 'collocation',
    example: 'Un juzgado de Madrid ha dado la razón a los trabajadores '
        'despedidos.',
  ),
  // DLE s.v. tierra: «echar por tierra un argumento, una idea, un proyecto»
  // 'desbaratarlo'.
  SeedExpression(
    canonical: 'echar por tierra (algo)',
    searchForm: 'echar por tierra',
    glossRu: 'свести на нет; опровергнуть (версию, теорию)',
    kind: 'idiom',
    example: 'El nuevo estudio echa por tierra la teoría más aceptada hasta '
        'ahora.',
  ),
  // DLE s.v. cargo: «hacerse cargo de algo» 'encargarse de ello'.
  SeedExpression(
    canonical: 'hacerse cargo de (algo)',
    searchForm: 'hacerse cargo',
    glossRu: 'взять на себя (расходы, руководство)',
    kind: 'collocation',
    example: 'El Estado se hará cargo de los gastos de la reconstrucción.',
  ),
  // DLE s.v. ojo: «ojo del huracán», 2 'centro de una situación polémica o
  // conflictiva'.
  SeedExpression(
    canonical: 'estar en el ojo del huracán',
    searchForm: 'en el ojo del huracán',
    glossRu: 'быть в эпицентре скандала, в центре бури',
    kind: 'idiom',
    example: 'La aerolínea está en el ojo del huracán por las cancelaciones '
        'del verano.',
  ),
  // DLE s.v. eco: «hacerse alguien eco de algo» 'contribuir a la difusión de
  // una noticia, rumor, etc.'.
  SeedExpression(
    canonical: 'hacerse eco de (algo)',
    searchForm: 'hacerse eco',
    glossRu: 'подхватить и распространить (новость, слух)',
    kind: 'collocation',
    example: 'La prensa internacional se hace eco de las protestas.',
  ),
  // DLE s.v. coto: «poner coto a algo» 'impedir que continúe algo negativo,
  // como desmanes o abusos'.
  SeedExpression(
    canonical: 'poner coto a (algo)',
    searchForm: 'poner coto',
    glossRu: 'положить конец (злоупотреблениям), обуздать',
    kind: 'idiom',
    example: 'El Gobierno regional quiere poner coto a los pisos turísticos '
        'ilegales.',
  ),
  // DLE s.v. cumplir, 1 'llevar a efecto'. Trap, same verb: «se cumple el
  // plazo» (cumplir, 6) means the deadline EXPIRES.
  SeedExpression(
    canonical: 'cumplir (con) los plazos',
    searchForm: 'cumplir los plazos',
    glossRu: 'уложиться в сроки, соблюдать сроки',
    kind: 'collocation',
    example: 'La constructora no ha cumplido los plazos y la obra acumula un '
        'año de retraso.',
  ),
  // DLE s.v. fondo: «tocar fondo» 'llegar al límite de una situación
  // desfavorable'.
  SeedExpression(
    canonical: 'tocar fondo',
    searchForm: 'tocar fondo',
    glossRu: 'достичь дна (худшей точки)',
    kind: 'idiom',
    example: 'Los analistas creen que el mercado inmobiliario ya ha tocado '
        'fondo.',
  ),
  // DLE s.v. cuenta, 6 'razón, satisfacción de algo'; Fundéu proposes
  // «rendición de cuentas» for «accountability».
  SeedExpression(
    canonical: 'rendir cuentas (ante alguien)',
    searchForm: 'rendir cuentas',
    glossRu: 'отчитываться, держать ответ (перед кем-л.)',
    kind: 'collocation',
    example: 'La nueva ley obliga a los altos cargos a rendir cuentas ante el '
        'Parlamento.',
  ),
  // DLE s.v. vista: «hacer alguien la vista gorda», coloq. 'fingir con
  // disimulo que no ha visto algo'.
  SeedExpression(
    canonical: 'hacer la vista gorda (ante algo)',
    searchForm: 'hacer la vista gorda',
    glossRu: 'закрывать глаза (на что-л.), смотреть сквозь пальцы',
    kind: 'idiom',
    register: 'coloquial',
    example: 'Durante años, los inspectores hicieron la vista gorda ante las '
        'obras ilegales.',
  ),
  // DLE s.v. caso: «hacer caso omiso» 'prescindir de algo o no tenerlo en
  // cuenta'; «de» is the traditional preposition («a» is also heard).
  SeedExpression(
    canonical: 'hacer caso omiso de (algo)',
    searchForm: 'hacer caso omiso',
    // Not «пропустить мимо ушей» (ironic, speech only, can be accidental).
    glossRu: 'проигнорировать, сознательно пренебречь (предупреждением, '
        'приказом, запретом), не принять во внимание',
    kind: 'collocation',
    example: 'Muchos conductores hicieron caso omiso de las advertencias y '
        'salieron a la carretera.',
  ),
  // DLE s.v. balón: «echar, o lanzar, balones fuera», coloqs. 'responder con
  // evasivas, o eludir una situación comprometida'.
  SeedExpression(
    canonical: 'echar balones fuera',
    searchForm: 'echar balones fuera',
    glossRu: 'уходить от ответа, уклоняться от ответственности',
    kind: 'idiom',
    register: 'coloquial',
    example: 'Preguntado por el apagón, el consejero echó balones fuera y '
        'culpó a la compañía eléctrica.',
  ),
  // DLE s.v. punto: «punto muerto», 1 'estado de un asunto o negociación que…
  // no puede de momento llevarse adelante'.
  SeedExpression(
    canonical: 'estar en punto muerto',
    searchForm: 'en punto muerto',
    glossRu: 'зайти в тупик, застыть на мёртвой точке',
    kind: 'idiom',
    example: 'Las conversaciones de paz siguen en punto muerto.',
  ),
  // DLE s.v. mella: «hacer mella» 'causar efecto…; ocasionar pérdida'.
  SeedExpression(
    canonical: 'hacer mella (en algo)',
    searchForm: 'hacer mella',
    glossRu: 'подорвать, пошатнуть; сказаться (на чём-л.)',
    kind: 'idiom',
    example: 'La subida de los tipos de interés empieza a hacer mella en el '
        'consumo.',
  ),
  // DLE s.v. carta: «tomar cartas en algún negocio», coloq. 'intervenir en
  // él'.
  SeedExpression(
    canonical: 'tomar cartas en el asunto',
    searchForm: 'tomar cartas en el asunto',
    glossRu: 'вмешаться, взяться за дело',
    kind: 'idiom',
    register: 'coloquial',
    example: 'La Fiscalía ha tomado cartas en el asunto tras la denuncia de '
        'los vecinos.',
  ),
  // DLE s.v. oído: «hacer alguien oídos sordos» 'no atender, no darse por
  // enterado de lo que se dice'.
  SeedExpression(
    canonical: 'hacer oídos sordos (a algo)',
    searchForm: 'hacer oídos sordos',
    glossRu: 'оставаться глухим (к чему-л.), пропускать мимо ушей',
    kind: 'idiom',
    example: 'La dirección hizo oídos sordos a las quejas de la plantilla.',
  ),
  // DLE s.v. pie: «en pie de guerra», 3 'preparado para una acción intensa'.
  SeedExpression(
    canonical: 'estar en pie de guerra',
    searchForm: 'en pie de guerra',
    glossRu: 'быть на тропе войны, готовиться к борьбе (о протестующих)',
    kind: 'idiom',
    example: 'Los taxistas están en pie de guerra contra las nuevas licencias '
        'de VTC.',
  ),
  // DLE s.v. puerta: «a puerta cerrada» 'secretamente'.
  SeedExpression(
    canonical: 'a puerta cerrada',
    searchForm: 'a puerta cerrada',
    glossRu: 'за закрытыми дверями',
    kind: 'idiom',
    example: 'Los líderes de ambos partidos se reunieron a puerta cerrada '
        'durante tres horas.',
  ),
  // DLE s.v. caldo: «caldo de cultivo», 2 'ambiente propicio para que algo se
  // desarrolle' (in the press, mostly something negative).
  SeedExpression(
    canonical: 'ser (un) caldo de cultivo (para algo)',
    searchForm: 'caldo de cultivo',
    glossRu: 'питательная среда, благодатная почва (обычно для негативного)',
    kind: 'idiom',
    example: 'Los expertos advierten de que la precariedad es un caldo de '
        'cultivo para el descontento.',
  ),
  // DLE s.v. agua: «hacer agua», 1 'dicho de un proyecto: presentar
  // debilidad o síntomas de ir a fracasar'; «hacer aguas» = 'orinar'. The
  // DPD admits «hacer aguas» figuratively but recommends the distinction.
  SeedExpression(
    canonical: 'hacer agua',
    searchForm: 'hacer agua',
    glossRu: 'трещать по швам, давать течь (о плане, проекте)',
    kind: 'idiom',
    example: 'El plan de digitalización hace agua por falta de personal '
        'técnico.',
  ),
  // DLE s.v. hombro: «arrimar el hombro» 'trabajar con actividad, ayudar o
  // contribuir al logro de un fin'.
  SeedExpression(
    canonical: 'arrimar el hombro',
    searchForm: 'arrimar el hombro',
    // Not «подставить плечо кому-л.» (that is apoyar / echar una mano).
    glossRu: 'внести свою лепту, включиться в общее дело, приложить усилия '
        'сообща',
    kind: 'idiom',
    example: 'El alcalde ha pedido a todos los grupos que arrimen el hombro '
        'ante la emergencia.',
  ),
  // DLE s.v. vuelta: «a la vuelta de la esquina» 'muy próximo… muy a mano';
  // in the press mostly about time.
  SeedExpression(
    canonical: 'estar a la vuelta de la esquina',
    searchForm: 'a la vuelta de la esquina',
    glossRu: 'совсем рядом; не за горами',
    kind: 'idiom',
    example: 'Con las elecciones a la vuelta de la esquina, los partidos '
        'aceleran sus campañas.',
  ),
  // DLE s.v. costa: «a toda costa» 'sin limitación en el gasto o en el
  // trabajo'.
  SeedExpression(
    canonical: 'a toda costa',
    searchForm: 'a toda costa',
    glossRu: 'любой ценой',
    kind: 'idiom',
    example: 'La empresa quiere evitar a toda costa el cierre de la planta.',
  ),
  // DLE s.v. papel: «papel mojado», 1 'papel de poca importancia o que prueba
  // poco' (unmarked; the coloq. sense 2 is 'cosa inútil').
  SeedExpression(
    canonical: 'quedar(se) en papel mojado',
    searchForm: 'papel mojado',
    glossRu: 'пустая бумажка; остаться на бумаге (о законе, договоре)',
    kind: 'idiom',
    example: 'Sin inspectores suficientes, la nueva ordenanza puede quedarse '
        'en papel mojado.',
  ),
  // DLE s.v. cabeza: «cabeza de turco» (m. y f.) 'persona a quien se achacan
  // todas las culpas para eximir a otras'.
  SeedExpression(
    canonical: 'ser el/la cabeza de turco',
    searchForm: 'cabeza de turco',
    glossRu: 'козёл отпущения',
    kind: 'idiom',
    example: 'Los sindicatos denuncian que el maquinista se ha convertido en '
        'el cabeza de turco del accidente.',
  ),
  // DLE s.v. brindis: «brindis al sol», Esp. 'cosa que se hace o dice… para
  // obtener algún beneficio, sabiendo que será inviable'.
  SeedExpression(
    canonical: 'ser un brindis al sol',
    searchForm: 'brindis al sol',
    glossRu: 'пустое, заведомо невыполнимое обещание; жест на публику',
    kind: 'idiom',
    region: 'es-ES',
    example: 'La oposición califica de brindis al sol la promesa de construir '
        '50.000 viviendas.',
  ),
  // DLE s.v. pecho: «sacar alguien pecho», coloq. 'adoptar una actitud de
  // orgullo'.
  SeedExpression(
    canonical: 'sacar pecho (de algo)',
    searchForm: 'sacar pecho',
    glossRu: 'гордо выпячивать грудь, хвалиться (успехами)',
    kind: 'idiom',
    register: 'coloquial',
    example: 'El Gobierno saca pecho de los datos de empleo del verano.',
  ),
  // DLE s.v. grito: «poner el grito en el cielo», coloq. 'quejarse
  // vehementemente de algo'.
  SeedExpression(
    canonical: 'poner el grito en el cielo',
    searchForm: 'poner el grito en el cielo',
    glossRu: 'поднять крик, бурно возмущаться',
    kind: 'idiom',
    register: 'coloquial',
    example: 'Los hosteleros han puesto el grito en el cielo por la nueva '
        'tasa turística.',
  ),
  // DLE s.v. pila: «ponerse alguien las pilas», coloq. 'disponerse a
  // emprender algo con energía y resolución'.
  SeedExpression(
    canonical: 'ponerse las pilas',
    searchForm: 'ponerse las pilas',
    glossRu: 'собраться, взяться за дело всерьёз',
    kind: 'idiom',
    register: 'coloquial',
    example: 'Los expertos creen que las Administraciones deben ponerse las '
        'pilas en ciberseguridad.',
  ),
  // DLE s.v. sartén: «tener alguien la sartén por el mango», coloq. 'ser
  // dueño de la situación'.
  SeedExpression(
    canonical: 'tener la sartén por el mango',
    searchForm: 'tener la sartén por el mango',
    glossRu: 'быть хозяином положения, держать всё в своих руках',
    kind: 'idiom',
    register: 'coloquial',
    example: 'Con mayoría absoluta, el partido tiene la sartén por el mango en '
        'el Parlamento.',
  ),
  // DLE s.v. espada: «entre la espada y la pared», coloq. 'en situación muy
  // comprometida ante dos opciones difíciles'.
  SeedExpression(
    canonical: 'estar entre la espada y la pared',
    searchForm: 'entre la espada y la pared',
    glossRu: 'между молотом и наковальней',
    kind: 'idiom',
    register: 'coloquial',
    example: 'La subida del gasóleo deja a los transportistas entre la espada '
        'y la pared.',
  ),
  // DLE s.v. gota: «ser algo la gota que colma el vaso», coloqs. 'ser lo que
  // viene a colmar la medida de la paciencia'.
  SeedExpression(
    canonical: 'ser la gota que colma el vaso',
    searchForm: 'la gota que colma el vaso',
    glossRu: 'последняя капля (переполнившая чашу)',
    kind: 'idiom',
    register: 'coloquial',
    example: 'El último apagón ha sido la gota que colma el vaso para los '
        'vecinos del barrio.',
  ),
  // DLE s.v. agua: «agua de borrajas» 'cosa de poca o ninguna importancia…
  // U. m. en la fr. quedar algo en agua de borrajas'.
  SeedExpression(
    canonical: 'quedar(se) en agua de borrajas',
    searchForm: 'agua de borrajas',
    glossRu: 'закончиться ничем, выйти пшиком',
    kind: 'idiom',
    example: 'La reforma prometida quedó en agua de borrajas tras el cambio de '
        'gobierno.',
  ),
];
