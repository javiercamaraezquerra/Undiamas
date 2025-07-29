import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class ResourcesScreen extends StatefulWidget {
  const ResourcesScreen({super.key});
  @override
  State<ResourcesScreen> createState() => _ResourcesScreenState();
}

class _ResourcesScreenState extends State<ResourcesScreen> {
  /* ───────── datos internos ───────── */
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

  String _query = '';
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

  /* ───────── UI ───────── */
  @override
  Widget build(BuildContext context) {
    final filtered = _all.where((r) {
      final okCat = _category == 'Todos' || r.category == _category;
      final okText =
          _query.isEmpty || r.title.toLowerCase().contains(_query.toLowerCase());
      return okCat && okText;
    }).toList();

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('Recursos')),
      body: SafeArea(               // ← desplazamos el contenido bajo la barra
        top: true,
        bottom: false,
        child: Column(
          children: [
            // ── Buscador ──
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar…',
                ),
                onChanged: (q) => setState(() => _query = q),
              ),
            ),

            // ── Chips de categoría ──
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

            // ── Lista de recursos ──
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final r = filtered[i];
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
      ),
    );
  }

  /* ───────── Detalle modal ───────── */
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
                      await launchUrl(uri,
                          mode: LaunchMode.externalApplication);
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

/* ─────────────────── Modelo ─────────────────── */
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

// ───────────────── Lista de recursos verificados (jul-2025) ─────────────────
final List<_Resource> _resources = [
  // ── CONOCIMIENTO ───────────────────────────────────────────────
  _Resource(
    id: 'neuro',
    title: 'La ciencia de la adicción (NIDA)',
    category: 'Conocimiento',
    content:
        'Folleto ilustrado que explica cómo las drogas alteran el cerebro y por qué '
        'la adicción es una enfermedad crónica.',
    url: 'https://nida.nih.gov/sites/default/files/soa_sp_2014.pdf',
    type: _ResType.pdf,
  ),
  _Resource(
    id: 'triggers',
    title: 'Factores internos y externos de recaída',
    category: 'Conocimiento',
    content:
        'Artículo que describe detonantes emocionales y situacionales y propone estrategias para manejarlos.',
    url:
        'https://fundacionliberate.org.co/adiccion-al-alcohol-o-las-drogas-factores-internos-y-externos/',
    type: _ResType.web,
  ),

  // ── ESTRATEGIAS ────────────────────────────────────────────────
  _Resource(
    id: 'urge',
    title: 'Guion de meditación “Urge-surfing”',
    category: 'Estrategias',
    content:
        'Script paso a paso (4 pág.) para “surfear” la ola de craving sin ceder al impulso.',
    url:
        'https://www.therapistaid.com/worksheets/urge-surfing-script?language=es',
    type: _ResType.pdf,
  ),
  _Resource(
    id: 'relapse',
    title: 'Manual del Programa de Prevención de Recaídas',
    category: 'Estrategias',
    content:
        'Guía CONADIC (152 págs.) basada en el modelo Marlatt & Gordon, con ejercicios prácticos.',
    url:
        'https://raulmartindelcampo.files.wordpress.com/2016/11/manual-recaidas-mexico-1.pdf',
    type: _ResType.pdf,
  ),
  _Resource(
    id: 'thought_record',
    title: 'Registro de pensamientos (TCC) – hoja de trabajo',
    category: 'Estrategias',
    content:
        'Plantilla de Therapist Aid (1 pág.) para identificar y reestructurar pensamientos automáticos.',
    url:
        'https://www.therapistaid.com/worksheets/thought-record?language=es',
    type: _ResType.pdf,
  ),
  _Resource(
    id: 'warning',
    title: 'Señales de alarma: infografía',
    category: 'Estrategias',
    content:
        'Infografía que resume síntomas físicos, psicológicos y sociales indicativos de riesgo.',
    url:
        'https://www.javeriana.edu.co/enmental/wp-content/uploads/2024/12/04-Infografia-Cuales-son-los-signos-de-alarma-que-pueden-indicar-dependencia-hacia-drogas-V4.pdf',
    type: _ResType.pdf,
  ),

  // ── BIENESTAR ──────────────────────────────────────────────────
  _Resource(
    id: 'exercise',
    title: 'Beneficios del ejercicio en adicciones',
    category: 'Bienestar',
    content:
        'Cómo la actividad física reduce el craving y mejora el estado de ánimo.',
    url:
        'https://orbiumadicciones.com/bienestar/beneficios-del-ejercicio-fisico-en-el-tratamiento-de-las-adicciones/',
    type: _ResType.web,
  ),
  _Resource(
    id: 'selfcomp',
    title: 'Ejercicios de autocompasión (Kristin Neff)',
    category: 'Bienestar',
    content:
        'Cuaderno breve (9 pág.) que adapta los ejercicios del libro “Sé amable contigo mismo”.',
    url:
        'https://eliarocapsicologa.wordpress.com/wp-content/uploads/2019/01/neff-ejercicios-se-amable.pdf',
    type: _ResType.pdf,
  ),
  _Resource(
    id: 'detox',
    title: 'Detox digital: por qué y cómo',
    category: 'Bienestar',
    content:
        'Consejos prácticos para reducir el tiempo de pantalla y mejorar la salud mental.',
    url: 'https://conecta.tec.mx/es/noticias/nacional/salud/detox-digital',
    type: _ResType.web,
  ),

  // ── FAMILIA ────────────────────────────────────────────────────
  _Resource(
    id: 'craft',
    title: 'CRAFT: Comunicarte con tus seres queridos',
    category: 'Familia',
    content:
        'Artículo-web y audio (Cigna, 2022) que explica paso a paso el enfoque CRAFT para apoyar sin confrontar.',
    url:
        'https://www.cigna.com/es-us/knowledge-center/substance-use-disorders-seminars/craft',
    type: _ResType.web,
  ),

  // ── SUEÑO ──────────────────────────────────────────────────────
  _Resource(
    id: 'sleep',
    title: 'Guía práctica para dormir bien',
    category: 'Sueño',
    content:
        'Consejos de higiene del sueño y ejercicios de relajación (Comunidad de Madrid).',
    url: 'https://www.madrid.org/bvirtual/BVCM050390.pdf',
    type: _ResType.pdf,
  ),
  _Resource(
    id: 'sleep_diary',
    title: 'Diario de sueño (7 días) – Therapist Aid',
    category: 'Sueño',
    content:
        'Registro matutino y nocturno en español para monitorizar hábitos y calidad del sueño durante una semana.',
    url:
        'https://www.therapistaid.com/worksheets/sleep-diary?language=es',
    type: _ResType.pdf,
  ),

  // ── NUTRICIÓN ──────────────────────────────────────────────────
  _Resource(
    id: 'nutrition',
    title: 'Dieta y recuperación de la drogadicción',
    category: 'Nutrición',
    content:
        'Artículo MedlinePlus que detalla el papel de los nutrientes durante la abstinencia de distintas sustancias.',
    url:
        'https://medlineplus.gov/spanish/ency/article/002149.htm',
    type: _ResType.web,
  ),

  // ── FAQ ────────────────────────────────────────────────────────
  _Resource(
    id: 'faq',
    title: 'Preguntas frecuentes sobre adicciones',
    category: 'FAQ',
    content:
        'Hospital Clínic Barcelona: preguntas y respuestas comunes sobre tratamiento y recaída.',
    url:
        'https://www.clinicbarcelona.org/asistencia/enfermedades/adicciones/preguntas-frecuentes',
    type: _ResType.web,
  ),

  // ── MULTIMEDIA ────────────────────────────────────────────────
  _Resource(
    id: 'podcast',
    title: 'Podcast “Adiós Adicción”',
    category: 'Multimedia',
    content:
        'Testimonios y herramientas prácticas para mantener la sobriedad (Spotify).',
    url: 'https://open.spotify.com/show/3yGznj4I9JbG8qFW1ebs4N',
    type: _ResType.podcast,
  ),
  _Resource(
    id: 'mindfulness',
    title: 'Audio mindfulness: pausa de 3 minutos',
    category: 'Multimedia',
    content:
        'Meditación guiada breve para centrar la atención y calmar la mente.',
    url: 'https://www.youtube.com/watch?v=jh2nMVmkM1o',
    type: _ResType.video,
  ),
  _Resource(
    id: 'box_breath',
    title: 'Respiración en caja 4-4-4-4',
    category: 'Multimedia',
    content:
        'Vídeo guiado (5 min) para activar el sistema parasimpático y reducir el estrés.',
    url: 'https://www.youtube.com/watch?v=7lwvDIBppP0',
    type: _ResType.video,
  ),
];

