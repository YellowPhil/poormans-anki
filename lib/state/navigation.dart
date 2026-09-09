import 'package:flutter_riverpod/flutter_riverpod.dart';

sealed class Destination {
  const Destination();
}

class DashboardDestination extends Destination {
  const DashboardDestination();

  @override
  bool operator ==(Object other) => other is DashboardDestination;

  @override
  int get hashCode => 1;
}

/// [deckId] null reviews every deck.
class InboxDestination extends Destination {
  const InboxDestination({this.deckId});

  final String? deckId;

  @override
  bool operator ==(Object other) =>
      other is InboxDestination && other.deckId == deckId;

  @override
  int get hashCode => Object.hash(2, deckId);
}

class DeckDestination extends Destination {
  const DeckDestination(this.deckId);

  final String deckId;

  @override
  bool operator ==(Object other) =>
      other is DeckDestination && other.deckId == deckId;

  @override
  int get hashCode => Object.hash(3, deckId);
}

class SearchDestination extends Destination {
  const SearchDestination();

  @override
  bool operator ==(Object other) => other is SearchDestination;

  @override
  int get hashCode => 4;
}

/// Full-screen editor; desktop opens the same editor in a dialog instead.
class AddDestination extends Destination {
  const AddDestination({this.deckId});

  final String? deckId;

  @override
  bool operator ==(Object other) =>
      other is AddDestination && other.deckId == deckId;

  @override
  int get hashCode => Object.hash(5, deckId);
}

class DestinationNotifier extends Notifier<Destination> {
  @override
  Destination build() => const InboxDestination();

  void go(Destination destination) => state = destination;
}

final destinationProvider = NotifierProvider<DestinationNotifier, Destination>(
  DestinationNotifier.new,
);
