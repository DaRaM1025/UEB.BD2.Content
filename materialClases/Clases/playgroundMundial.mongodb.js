/* global use, db */
// MongoDB Playground
// To disable this template go to Settings | MongoDB | Use Default Template For Playground.
// Make sure you are connected to enable completions and to be able to run a playground.
// Use Ctrl+Space inside a snippet or a string literal to trigger completions.
// The result of the last command run in a playground is shown on the results panel.
// By default the first 20 documents will be returned with a cursor.
// Use 'console.log()' to print to the debug output.
// For more documentation on playgrounds please refer to
// https://www.mongodb.com/docs/mongodb-vscode/playgrounds/

// Select the database to use.
use('mundial2026');

// Insert a few documents into the selecciones collection.
db.jugadores.insertMany([
    {'nombre': 'James Rodríguez', 'nacionalidad': 'colombia', 'posicion': 'centrocampista', 'goles': 80, 'asistencias': 50, 'partidos': 200, 'lesiones': [{'lugar': 'cadera', 'descripcion': 'lesión muscular', 'duracion': '2 semanas'}]},
    {'nombre': 'Sergio Ramos', 'nacionalidad': 'españa', 'posicion': 'defensor', 'goles': 50, 'asistencias': 20, 'partidos': 350, 'lesiones': [{'lugar': 'rodilla', 'descripcion': 'lesión ligamentosa', 'duracion': '1 mes'}]},
    {'nombre': 'Manuel Neuer', 'nacionalidad': 'alemania', 'posicion': 'portero', 'goles': 0, 'asistencias': 5, 'partidos': 400, 'lesiones': [{'lugar': 'mano', 'descripcion': 'fractura de dedo', 'duracion': '3 semanas'}]},
    {'nombre': 'Ángel Di María', 'nacionalidad': 'argentina', 'posicion': 'delantero', 'goles': 150, 'asistencias': 100}
]);
db.estadios.insertMany([
    { 'nombre': 'estadio azteca', 'ciudad': 'ciudad de mexico', 'capacidad': 87000 },
    { 'nombre': 'maracaná', 'ciudad': 'rio de janeiro', 'capacidad': 78000 },
    { 'nombre': 'santiago bernabéu', 'ciudad': 'madrid', 'capacidad': 81000 },
    { 'nombre': 'allianz arena', 'ciudad': 'munich', 'capacidad': 75000 },
    { 'nombre': 'parque de los príncipes', 'ciudad': 'paris', 'capacidad': 48000 }
]);

db.jugadores.insertMany([
    { 'nombre': 'lionel messi', 'nacionalidad': 'argentina', 'posicion': 'delantero', 'goles': 700 },
    { 'nombre': 'cristiano ronaldo', 'nacionalidad': 'portugal', 'posicion': 'delantero', 'goles': 750 },
    { 'nombre': 'neymar', 'nacionalidad': 'brasil', 'posicion': 'delantero', 'goles': 400, 'asistencias': 200 ,'partidos': 500 },
    { 'nombre': 'kylian mbappé', 'nacionalidad': 'francia', 'posicion': 'delantero', 'goles': 200, 'asistencias': 100, 'partidos': 300 },
    { 'nombre': 'robert lewandowski', 'nacionalidad': 'polonia', 'posicion': 'delantero', 'goles': 500, 'asistencias': 150, 'partidos': 600 },
    { 'nombre': 'kevin de bruyne', 'nacionalidad': 'belgica', 'posicion': 'centrocampista', 'goles': 100, 'asistencias': 300, 'partidos': 400 },
    { 'nombre': 'virgil van dijk', 'nacionalidad': 'paises bajos', 'posicion': 'defensor', 'goles': 50, 'asistencias': 20, 'partidos': 350 },
    { 'nombre': 'alisson becker', 'nacionalidad': 'brasil', 'posicion': 'portero', 'goles': 0}
    ]);
    
    db.selecciones.insertMany([
      { 'nombre': 'inglaterra', 'colorCamiseta': 'amarilla', 'capital': 'londres', 'poblacion': 64214000 },
      { 'nombre': 'francia', 'colorCamiseta': 'azul', 'capital': 'paris', 'poblacion': 2161000 },
      { 'nombre': 'españa', 'colorCamiseta': 'verde', 'capital': 'madrid', 'poblacion': 3266000 },
      { 'nombre': 'alemania', 'colorCamiseta': 'blanca', 'capital': 'berlin', 'poblacion': 8310000 },
      { 'nombre': 'argentina', 'colorCamiseta': 'celeste', 'capital': 'buenos aires', 'poblacion': 4310000 },
      { 'nombre': 'brasil', 'colorCamiseta': 'verde', 'capital': 'brasilia', 'poblacion': 2110000 },
      { 'nombre': 'colombia', 'colorCamiseta': 'amarilla', 'capital': 'bogotá', 'poblacion': 4900000 },
      { 'nombre': 'uruguay', 'colorCamiseta': 'celeste', 'capital': 'montevideo', 'poblacion': 3500000 },
      { 'nombre': 'mexico', 'colorCamiseta': 'verde', 'capital': 'ciudad de mexico', 'poblacion': 1260000 }
    ]);
