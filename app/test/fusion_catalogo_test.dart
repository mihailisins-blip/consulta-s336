// fusion_catalogo.dart (R22/KTD5/U15): fusionar dos entradas del catálogo
// reasigna todos sus enlaces de actividad y sus alias a la superviviente,
// sin dejar referencias colgando, y deja un registro para deshacerla.

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:consulta_s336_app/curacion/fusion_catalogo.dart';
import 'package:consulta_s336_app/data/queries.dart';

import 'helpers/minimal_db.dart';

void main() {
  late Database db;
  setUp(() => db = openMinimalTestDb());
  tearDown(() => db.dispose());

  void seedDosEntradas() {
    db.execute('''
      INSERT INTO catalogo (id,codigo_erp,descripcion,fabricante,unidad,tipo) VALUES
        ('cat:super','20027','Aceite reductor Mobil 75W-90','Mobil','L','material'),
        ('cat:perdedor','','Aceite reductor MOBIL 75W90 (duplicado)',null,'L','material')
    ''');
    db.execute('''
      INSERT INTO actividad (codigo,sistema_codigo,vmi_rel_path,sin_extraer,componente,actividad_tipo,operacion,frecuencia,edicion)
      VALUES
        ('FD5.01.01','FD5','x/a.pdf',0,'REDUCTOR','INSPECCIÓN','Nivel de aceite','Mensual','--'),
        ('FD5.01.02','FD5','x/b.pdf',0,'REDUCTOR','SUSTITUCIÓN','Cambio de aceite','Anual','--')
    ''');
    db.execute('''
      INSERT INTO actividad_material (actividad_codigo,catalogo_id,cant,cant_num,ud,uso,reserva,fuente) VALUES
        ('FD5.01.01','cat:super','2','2','L','S',0,'materiales'),
        ('FD5.01.02','cat:perdedor','5','5','L','S',0,'materiales')
    ''');
    db.execute("INSERT INTO catalogo_alias (catalogo_id, alias) VALUES ('cat:perdedor', 'MOBIL 75W90 antiguo')");
    db.execute("INSERT INTO busqueda (tipo, ref, titulo, cuerpo) VALUES ('catalogo','cat:perdedor','x','y')");
  }

  test('fusionar mueve todos los enlaces de actividad a la superviviente, y borra la perdedora', () {
    seedDosEntradas();

    fusionarCatalogo(db, supervivienteId: 'cat:super', perdedorId: 'cat:perdedor');

    // la perdedora ya no existe en el catálogo
    expect(db.select("SELECT 1 FROM catalogo WHERE id='cat:perdedor'"), isEmpty);
    // ni en el índice de búsqueda -- sin ella, quedaría una entrada muerta
    expect(db.select("SELECT 1 FROM busqueda WHERE ref='cat:perdedor'"), isEmpty);

    // el enlace que apuntaba a la perdedora ahora apunta a la superviviente
    final materiales = materialesDeActividadParaExport(db, 'FD5.01.02');
    expect(materiales, hasLength(1));
    expect(materiales.single.codigoErp, '20027');

    // no quedan referencias colgando a 'cat:perdedor' en ningún enlace
    expect(db.select("SELECT 1 FROM actividad_material WHERE catalogo_id='cat:perdedor'"), isEmpty);

    // su alias también se movió, y su propia descripción quedó como alias nuevo
    final alias = db.select("SELECT alias FROM catalogo_alias WHERE catalogo_id='cat:super'").map((r) => r['alias']);
    expect(alias, containsAll(['MOBIL 75W90 antiguo', 'Aceite reductor MOBIL 75W90 (duplicado)']));
  });

  test('fusionar consigo misma lanza, no fusiona en silencio', () {
    seedDosEntradas();
    expect(
      () => fusionarCatalogo(db, supervivienteId: 'cat:super', perdedorId: 'cat:super'),
      throwsA(isA<FusionCatalogoException>()),
    );
  });

  test('deshacer una fusión restaura la entrada perdedora y sus enlaces originales', () {
    seedDosEntradas();
    fusionarCatalogo(db, supervivienteId: 'cat:super', perdedorId: 'cat:perdedor');
    final fusionId = db.select('SELECT id FROM fusion_catalogo').first['id'] as int;

    deshacerFusion(db, fusionId);

    // la entrada perdedora vuelve a existir, con sus datos originales
    final restaurada = db.select("SELECT * FROM catalogo WHERE id='cat:perdedor'");
    expect(restaurada, hasLength(1));
    expect(restaurada.first['descripcion'], 'Aceite reductor MOBIL 75W90 (duplicado)');

    // el enlace de FD5.01.02 vuelve a apuntar a la perdedora, no a la superviviente
    final materiales = materialesDeActividadParaExport(db, 'FD5.01.02');
    expect(materiales.single.codigoErp, ''); // 'cat:perdedor' se sembró con codigo_erp vacío
    expect(db.select("SELECT 1 FROM actividad_material WHERE actividad_codigo='FD5.01.02' AND catalogo_id='cat:perdedor'"), hasLength(1));

    // su alias original también vuelve
    expect(db.select("SELECT 1 FROM catalogo_alias WHERE catalogo_id='cat:perdedor' AND alias='MOBIL 75W90 antiguo'"), hasLength(1));

    // el enlace de FD5.01.01, que nunca fue de la perdedora, no se tocó
    expect(materialesDeActividadParaExport(db, 'FD5.01.01').single.codigoErp, '20027');
  });

  test('deshacer una fusión ya deshecha lanza', () {
    seedDosEntradas();
    fusionarCatalogo(db, supervivienteId: 'cat:super', perdedorId: 'cat:perdedor');
    final fusionId = db.select('SELECT id FROM fusion_catalogo').first['id'] as int;
    deshacerFusion(db, fusionId);
    expect(() => deshacerFusion(db, fusionId), throwsA(isA<FusionCatalogoException>()));
  });

  test('listFusionesPendientes solo lista las que no se han deshecho', () {
    seedDosEntradas();
    fusionarCatalogo(db, supervivienteId: 'cat:super', perdedorId: 'cat:perdedor');
    expect(listFusionesPendientes(db), hasLength(1));

    final fusionId = db.select('SELECT id FROM fusion_catalogo').first['id'] as int;
    deshacerFusion(db, fusionId);
    expect(listFusionesPendientes(db), isEmpty);
  });
}
