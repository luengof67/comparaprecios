import 'package:intl/intl.dart';

final _eur = NumberFormat.currency(locale: 'es_ES', symbol: '€', decimalDigits: 2);
final _eur3 = NumberFormat.currency(locale: 'es_ES', symbol: '€', decimalDigits: 3);
final _fecha = DateFormat('d MMM yyyy', 'es_ES');
final _fechaCorta = DateFormat('d MMM', 'es_ES');

String euros(num v) => _eur.format(v);
String euros3(num v) => _eur3.format(v); // util para €/kg con decimales finos
String fecha(DateTime d) => _fecha.format(d);
String fechaCorta(DateTime d) => _fechaCorta.format(d);
