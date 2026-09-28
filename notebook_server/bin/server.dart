import 'dart:async';
import 'dart:convert';

import 'package:mcp_server/mcp_server.dart';

import 'serve_bundle.dart';

/// notebook_server — a workshop notebook handed from one person to the next.
///
/// The hard part of inheriting someone's notes is not reading them. It is that
/// you cannot tell **who knew what, and when**. A line that says "loosen the
/// third valve half a turn in the rainy season" is worth everything if the
/// person who wrote it ran the machine for twenty years, and worth watching if
/// it was copied out of a manual by a temp.
///
/// So every line here carries three things it usually loses: who wrote it, when,
/// and what happened afterwards. And nothing is ever overwritten — a correction
/// is a new line that points back at the old one, so the previous owner's
/// judgement stays readable even after it turns out to be wrong.
void main(List<String> args) async {
  const config = McpServerConfig(
    name: 'Notebook',
    version: '1.0.0',
    capabilities: ServerCapabilities(
      tools: ToolsCapability(listChanged: true),
      resources: ResourcesCapability(listChanged: true),
    ),
  );
  final server = McpServer.createServer(config);
  NotebookServer(server).register();
  // The screen next door: AppPlayer reads it from here and sends the pages'
  // tool calls back to the tools above.
  registerBundleUi(server, '../notebook.mbd');
  final transport = McpServer.createStdioTransport().get();
  server.connect(transport);
  await Completer<void>().future;
}

/// One entry. Append-only: nothing here is ever edited in place.
class Note {
  const Note(this.id, this.who, this.year, this.machine, this.text,
      {this.supersedes, this.outcome = ''});

  final int id;
  final String who;
  final int year;
  final String machine;
  final String text;

  /// The id of the line this one corrects, if any. A correction never deletes.
  final int? supersedes;

  /// What actually happened after following this. Empty means nobody wrote it
  /// down, which is itself worth showing.
  final String outcome;
}

class NotebookServer {
  NotebookServer(this.server);

  final Server server;

  /// Two generations of a small workshop.
  final _notes = const [
    Note(1, 'Father', 1998, 'Press 2',
        'In the rainy season, back the third valve off half a turn.',
        outcome: 'ran without jamming that summer'),
    Note(2, 'Father', 2001, 'Press 2',
        'Warm it fifteen minutes before the first piece, not ten.',
        outcome: 'first-piece scrap dropped'),
    Note(3, 'Father', 2004, 'Lathe 1',
        'The chuck sings before it slips. Stop when it sings.'),
    Note(4, 'Son', 2019, 'Press 2',
        'New seal kit since 2018 — the valve trick is no longer needed.',
        supersedes: 1, outcome: 'no jams in two seasons without it'),
    Note(5, 'Son', 2021, 'Lathe 1',
        'Still true about the singing. Heard it twice.',
        outcome: 'caught both before slipping'),
    Note(6, 'Son', 2023, 'Press 2',
        'Fifteen minutes still right after the motor swap.',
        outcome: ''),
  ];

  void register() {
    server.addTool(
      name: 'notes.machine',
      description:
          'Every line ever written about one machine, oldest first, with who '
          'wrote it, when, what happened, and whether a later line corrects it',
      inputSchema: const {
        'type': 'object',
        'properties': {
          'machine': {'type': 'string'},
        },
      },
      handler: (args) async => _state(machine: args['machine'] as String?),
    );

    server.addTool(
      name: 'notes.standing',
      description:
          'What still stands: lines nothing has corrected. Superseded lines are '
          'not deleted, only marked.',
      inputSchema: const {'type': 'object', 'properties': {}},
      handler: (args) async => _state(standingOnly: true),
    );
  }

  CallToolResult _state({String? machine, bool standingOnly = false}) {
    final superseded = _notes
        .where((n) => n.supersedes != null)
        .map((n) => n.supersedes!)
        .toSet();

    var picked = _notes.where((n) => machine == null || n.machine == machine);
    if (standingOnly) {
      picked = picked.where((n) => !superseded.contains(n.id));
    }
    final list = picked.toList()..sort((a, b) => a.year.compareTo(b.year));

    final rows = list.map((n) {
      final by = superseded.contains(n.id)
          ? _notes.firstWhere((m) => m.supersedes == n.id)
          : null;
      return {
        'id': n.id,
        'who': n.who,
        'year': '${n.year}',
        'machine': n.machine,
        'text': n.text,
        // Absence is information. "nobody wrote it down" is not the same as
        // "it worked", and the screen must not let them look alike.
        'outcome': n.outcome.isEmpty ? 'not written down' : n.outcome,
        'hasOutcome': n.outcome.isNotEmpty,
        'superseded': by != null,
        // A corrected line keeps its text and gains a pointer. It never
        // disappears — the previous owner's reasoning stays readable.
        'correctedBy': by == null ? '' : '${by.who} ${by.year}: ${by.text}',
      };
    }).toList();

    final writers = list.map((n) => n.who).toSet().toList()..sort();
    final years = list.map((n) => n.year).toList()..sort();
    final noOutcome = list.where((n) => n.outcome.isEmpty).length;

    return CallToolResult(content: [
      TextContent(
        text: jsonEncode({
          'rows': rows,
          'rowCount': rows.length,
          // The book's own rule, printed on both sheets. It is the reason a
          // wrong line is still here rather than deleted.
          'bookRule': 'Nothing is removed · a correction is a new entry that '
              'names the one it supersedes',
          'writers': writers.join(' -> '),
          'span': years.isEmpty ? '' : '${years.first}-${years.last}',
          'supersededCount': rows.where((r) => r['superseded'] == true).length,
          'noOutcomeCount': noOutcome,
          'headline': years.isEmpty
              ? 'nothing written yet'
              : '${years.last - years.first} years, ${writers.length} hands',
        }),
      )
    ]);
  }
}
