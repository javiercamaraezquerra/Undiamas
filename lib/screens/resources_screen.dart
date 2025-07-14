import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class ResourcesScreen extends StatefulWidget {
  const ResourcesScreen({super.key});
  @override
  State<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends State<ResourcesScreen> {
  final List<_Resource> _all = _resources;
  final Set<String> _favorites = {};

  final List<String> _categories = [
    'Todos',
    'Conocimiento',
    'Estrategias',
    'Bienestar',
    'Familia',
    'Sueño',
    'Nutrición',
    'FAQ',
    'Multimedia',
  ];

  String _query    = '';
  String _category = 'Todos';

  @override
  void initState() {
    super.initState();
    _loadFavs();
  }

  Future<void> _loadFavs() async {
    final prefs = await SharedPreferences.getInstance();
    _favorites.addAll(prefs.getStringList('fav_resources') ?? []);
    setState(() {});
  }

  Future<void> _toggleFav(String id) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _favorites.contains(id) ? _favorites.remove(id) : _favorites.add(id);
      prefs.setStringList('fav_resources', _favorites.toList());
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _all.where((r) {
      final okCat  = _category == 'Todos' || r.category == _category;
      final okText = _query.isEmpty ||
          r.title.toLowerCase().contains(_query.toLowerCase());
      return okCat && okText;
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Recursos')),
      body: Column(
        children: [
          // ── Buscador ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar…',
                border: OutlineInputBorder(),
              ),
              onChanged: (q) => setState(() => _query = q),
            ),
          ),
          // ── Chips de categoría ─────────────────────────────────────
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: _categories
                  .map(
                    (c) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(c),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
          // ── Lista de recursos ──────────────────────────────────────
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: filtered.length,
              itemBuilder: (_, i) {
                final r   = filtered[i];
                final fav = _favorites.contains(r.id);
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    title: Text(r.title,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(r.category),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (r.url != null)
                          Icon(
                            r.typeIcon,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        IconButton(
                          icon: Icon(
                            fav ? Icons.star : Icons.star_border,
                            color: fav ? Colors.amber : null,
                          ),
                          onPressed: () => _toggleFav(r.id),
                        ),
                      ],
                    ),
                    onTap: () => _showDetail(context, r),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showDetail(BuildContext context, _Resource r) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        builder: (_, ctrl) => Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            controller: ctrl,
            children: [
              Text(r.title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(r.content, style: const TextStyle(fontSize: 16)),
              if (r.url != null) ...[
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: Icon(r.typeIcon),
                  label: const Text('Abrir recurso'),
                  onPressed: () async {
                    final uri = Uri.parse(r.url!);
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri, mode: LaunchMode.externalApplication);
                    } else {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Enlace no disponible 😕')),
                        );
                      }
                    }
                  },
                ),
              ],
              const SizedBox(height: 24),
              Center(
                child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cerrar')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────── Modelo + contenido verificado ───────────────────
enum _ResType { web, pdf, video, podcast }

class _Resource {
  final String id;
  final String title;
  final String content;
  final String category;
  final String? url;
  final _ResType type;

  const _Resource({
    required this.id,
    required this.title,
    required this.content,
    required this.category,
    required this.type,
    this.url,
  });

  IconData get typeIcon {
    switch (type) {
      case _ResType.pdf:
        return Icons.picture_as_pdf;
      case _ResType.video:
        return Icons.play_circle_fill;
      case _ResType.podcast:
        return Icons.podcasts;
      default:
        return Icons.open_in_new;
    }
  }
}

// Lista — enlaces comprobados 07 / 2025
final List<_Resource> _resources = [
  // ── CONOCIMIENTO ────────────────────────────────────────────────────
  _Resource(
    id: 'neuro',
    title: 'Neurobiología básica de la adicción',
    category: 'Conocimiento',
    content:
        'Explica por qué el circuito de recompensa, memoria y control se ve alterado.\n'
        'Versión en castellano del Institute on Drug Abuse (NIDA).',
    url:
        'https://archives.drugabuse.gov/sites/default/files/drugabuse_addiction_sp.pdf',
    type: _ResType.pdf,
  ),
  _Resource(
    id: 'triggers',
    title: 'Detonantes internos y externos',
    category: 'Conocimiento',
    content:
        'Identifica qué situaciones o emociones intensifican tus ganas de consumir y diseña respuestas saludables.',
    url:
        'https://www.prevencionar.com/wp-content/uploads/2020/05/Guia_identificar_disparadores.pdf',
    type: _ResType.pdf,
  ),

  // ── ESTRATEGIAS ─────────────────────────────────────────────────────
  _Resource(
    id: 'urge',
    title: 'Urge‑surfing paso a paso',
    category: 'Estrategias',
    content:
        'Ejercicio de 4 min para “surfear” la ola de ganas sin ceder al impulso.',
    url: 'https://www.youtube.com/watch?v=F3QTipnJXWI',
    type: _ResType.video,
  ),
  _Resource(
    id: 'relapse',
    title: 'Plan personal de prevención de recaídas',
    category: 'Estrategias',
    content:
        'Plantilla oficial SAMHSA (español) para anticipar señales y actuar a tiempo.',
    url:
        'https://store.samhsa.gov/sites/default/files/SAMHSA_Digital_Download/pep20-02-01-spa.pdf',
    type: _ResType.pdf,
  ),
  _Resource(
    id: 'thought_record',
    title: 'Registro de pensamientos (TCC)',
    category: 'Estrategias',
    content:
        'Cuestiona pensamientos automáticos y evita que detonen el consumo.',
    url:
        'https://www.fundacionmar.org.ar/images/fichas/registro-pensamientos.pdf',
    type: _ResType.pdf,
  ),
  _Resource(
    id: 'warning',
    title: 'Lista rápida de señales de alarma',
    category: 'Estrategias',
    content:
        'Checklist para saber cuándo pedir ayuda profesional o acudir a urgencias.',
    url:
        'https://cdn.isapps.com/isapps/resources/4/2029934/media/autoguia_senales_alarma.pdf',
    type: _ResType.pdf,
  ),

  // ── BIENESTAR ───────────────────────────────────────────────────────
  _Resource(
    id: 'exercise',
    title: 'Ejercicio: medicina gratis',
    category: 'Bienestar',
    content:
        'Caminar 20 min reduce la urgencia de consumir hasta 2 h y mejora tu ánimo.',
    type: _ResType.web,
  ),
  _Resource(
    id: 'selfcomp',
    title: 'Ejercicios de autocompasión',
    category: 'Bienestar',
    content:
        'Hoja de trabajo (Kristin Neff) para cultivar un diálogo interno amable.',
    url:
        'https://self-compassion.org/wp-content/uploads/2020/11/ejercicios-de-autocompasion.pdf',
    type: _ResType.pdf,
  ),
  _Resource(
    id: 'detox',
    title: 'Mini‑detox digital en 3 pasos',
    category: 'Bienestar',
    content:
        'Silencia notificaciones, crea “islas” sin móvil y sustituye el scroll por estiramientos.',
    type: _ResType.web,
  ),

  // ── FAMILIA ─────────────────────────────────────────────────────────
  _Resource(
    id: 'craft',
    title: 'Guía CRAFT para familias',
    category: 'Familia',
    content:
        'Método basado en evidencia para apoyar sin confrontar. PDF de la Junta de Castilla y León.',
    url:
        'https://www.lasdrogas.info/wp-content/uploads/2020/03/Guia-CRAFT-familias-2018.pdf',
    type: _ResType.pdf,
  ),

  // ── SUEÑO ───────────────────────────────────────────────────────────
  _Resource(
    id: 'sleep',
    title: 'Buenas prácticas de sueño',
    category: 'Sueño',
    content:
        'Rutina estable, habitación fresca y sin pantallas: claves para reparar tu cerebro.',
    type: _ResType.web,
  ),
  _Resource(
    id: 'sleep_diary',
    title: 'Diario de sueño (7 días)',
    category: 'Sueño',
    content:
        'Rellénalo cada mañana y noche para descubrir patrones que sabotean tu descanso.',
    url: 'https://www.sepeap.org/wp-content/uploads/2014/10/DIARIO-DE-SUEÑO.pdf',
    type: _ResType.pdf,
  ),

  // ── NUTRICIÓN ───────────────────────────────────────────────────────
  _Resource(
    id: 'nutrition',
    title: 'Guía rápida: comer para tu recuperación',
    category: 'Nutrición',
    content:
        'Proteínas en desayuno, carbohidratos complejos y omega‑3 ayudan a estabilizar el ánimo.',
    url:
        'https://www.fad.es/wp-content/uploads/2021/02/Guia_Nutricion_Adicciones.pdf',
    type: _ResType.pdf,
  ),

  // ── FAQ ─────────────────────────────────────────────────────────────
  _Resource(
    id: 'faq',
    title: 'Preguntas frecuentes sobre recaída',
    category: 'FAQ',
    content:
        'Duración típica de las ganas, cuándo buscar ayuda y por qué una recaída no es fracaso.',
    type: _ResType.web,
  ),

  // ── MULTIMEDIA ──────────────────────────────────────────────────────
  _Resource(
    id: 'podcast',
    title: 'Podcast “Sobriedad a la Carta”',
    category: 'Multimedia',
    content:
        'Historias de recuperación y entrevistas en castellano (Spotify).',
    url: 'https://open.spotify.com/show/5pNZWfG8tFvctgPpZ5NdZ8',
    type: _ResType.podcast,
  ),
  _Resource(
    id: 'mindfulness',
    title: 'Audio mindfulness 3 min (ES)',
    category: 'Multimedia',
    content:
        'Pausa breve guiada para centrar tu atención y bajar la ansiedad.',
    url: 'https://www.youtube.com/watch?v=ZTuR8tlkHH8',
    type: _ResType.video,
  ),
  _Resource(
    id: 'box_breath',
    title: 'Respiración cuadrada 4‑4‑4‑4 (ES)',
    category: 'Multimedia',
    content:
        'Vídeo guiado en castellano para activar tu sistema parasimpático.',
    url: 'https://www.youtube.com/watch?v=ngR5c7N4VaE',
    type: _ResType.video,
  ),
];
