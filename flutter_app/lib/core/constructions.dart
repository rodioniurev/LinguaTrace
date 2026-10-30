/// Closed list of "problem constructions" a Russian speaker typically gets
/// wrong in Spanish. The corrector must tag every fix with one of these, so
/// the same underlying error aggregates across different sentences — before,
/// mistakes were keyed by the exact string the model happened to cut, and
/// "my problem constructions" could never add up.
///
/// Sources: Torrellas Alonso 2025 (Domínios de Lingu@gem 19), Galaeva 2011
/// (Cuadernos de Rusística Española 7), Mañas et al. 2021 (CLAC), plus
/// contrastive predictions for Russian → Spanish.
library;

class Construction {
  final String tag;
  final String titleRu;
  final String exampleRu; // typical wrong → right, for prompts and UI

  const Construction(this.tag, this.titleRu, this.exampleRu);
}

const kSpanishConstructions = <Construction>[
  Construction('es.art.indef', 'Неопределённый артикль / его лишнее употребление',
      '*Tengo problema → Tengo un problema; *Soy un médico → Soy médico'),
  Construction('es.art.def', 'Определённый артикль с обобщающими и абстрактными',
      '*Vida en Madrid es cara → La vida…; *Me gustan perros → los perros'),
  Construction('es.ser_estar', 'ser / estar',
      '*Soy cansado → Estoy cansado; *La fiesta está en mi casa → es'),
  Construction('es.hay_estar', 'hay / estar',
      '*En la mesa está un libro → Hay un libro; *¿Dónde hay la farmacia? → está'),
  Construction('es.pret_imperf', 'Indefinido / imperfecto (вид глагола)',
      '*Ayer estaba dos horas en el médico → estuve; *Cuando fui niño → era'),
  Construction('es.perf_indef', 'Perfecto / indefinido (норма Испании)',
      '*Hoy me levanté a las 7 → me he levantado'),
  Construction('es.subj.temporal', 'Subjuntivo после cuando/hasta que о будущем',
      '*Cuando llegará Pedro → Cuando llegue Pedro'),
  Construction('es.subj.volition', 'Subjuntivo после желания, влияния, эмоции (чтобы)',
      '*Quiero que vienes → que vengas; *Me alegra que estás → estés'),
  Construction('es.subj.condition', 'Si-условные и como si',
      '*Si tendría tiempo → Si tuviera; *como si lo sabe → supiera'),
  Construction('es.negation', 'Двойное отрицание',
      '*Nadie no vino → Nadie vino / No vino nadie'),
  Construction('es.clitics', 'Местоимения lo/la/le, нейтральное lo, порядок',
      '*Sí, la es → Sí, lo es; *Lo gusta → Le gusta'),
  Construction('es.a_personal', 'Личное a (и его лишнее употребление)',
      '*Conozco tu hermana → a tu hermana; *Busco a un piso → Busco un piso'),
  Construction('es.regimen', 'Управление глагола (предлог после глагола)',
      '*Se casó en ella → con ella; *no me atrevo molestar → atrevo a molestar'),
  Construction('es.prep.place', 'Направление / место / транспорт (a, en)',
      '*Voy en la universidad → a la; *con autobús → en autobús'),
  Construction('es.por_para', 'por / para',
      '*Gracias para todo → por; *Estudio por trabajar aquí → para'),
  Construction('es.gender', 'Род и согласование',
      '*la problema → el problema; *el leche → la leche'),
  Construction('es.tense_sequence', 'Согласование времён в косвенной речи',
      '*Pensé que es fácil → era fácil'),
  Construction('es.motion_verbs', 'ir/venir, llevar/traer',
      '*Mañana te traigo el libro a tu casa → te llevo'),
  Construction('es.collocation', 'Сочетаемость (калька с русского)',
      '*dar una pregunta → hacer una pregunta; *dar atención → prestar atención'),
  Construction('es.false_friend', 'Ложные друзья переводчика',
      'фамилия ≠ familia (→ apellido); дата ≠ dato (→ fecha)'),
  Construction('es.reflexive', 'Возвратные глаголы (-ся ≠ se)',
      '*Quedo en casa → Me quedo; *Me espero que → Espero que'),
  Construction('es.word_order', 'Порядок слов (вопрос, наречия)',
      '*¿Dónde tu hermano trabaja? → ¿Dónde trabaja tu hermano?'),
  Construction('es.gerund', 'Герундий вместо причастия / придаточного',
      '*Los niños, paseando por el parque, … → que paseaban'),
  Construction('es.numerals', 'Числительные', '*cincuenta seis → cincuenta y seis'),
  Construction('es.spelling', 'Орфография и ударения', '*tambien → también'),
  Construction('es.punctuation', 'Пунктуация (¿ ¡, запятые)', '*Como estás? → ¿Cómo estás?'),
  Construction('es.idiom', 'Идиоматичность / устойчивое выражение',
      'дословный перевод вместо устойчивого оборота'),
  Construction('es.register', 'Регистр и стиль', 'слишком разговорно / канцелярит'),
  Construction('other', 'Другое', ''),
];

final kConstructionByTag = {
  for (final c in kSpanishConstructions) c.tag: c,
};

String constructionTitle(String tag) =>
    kConstructionByTag[tag]?.titleRu ?? (tag.isEmpty ? '' : tag);

/// Prompt fragment listing the allowed tags.
String constructionTagList() => kSpanishConstructions
    .map((c) => '- ${c.tag}: ${c.titleRu}')
    .join('\n');
