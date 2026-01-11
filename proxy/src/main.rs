use valence::prelude::*;

fn main() {
    App::new()
        .add_plugins((
            valence::ServerPlugin,
            valence::registry::RegistryPlugin,
            valence::registry::biome::BiomePlugin,
            valence::registry::dimension_type::DimensionTypePlugin,
            valence::entity::EntityPlugin,
            valence::layer::LayerPlugin,
            valence::client::ClientPlugin,
            valence::event_loop::EventLoopPlugin,
            valence::client_command::ClientCommandPlugin,
            valence::keepalive::KeepalivePlugin,
        ))
        // lol i should really look into a nicer way to do this since bevy only supports n number
        // of tuple plugins.
        .add_plugins((
            valence::teleport::TeleportPlugin,
            valence::message::MessagePlugin,
            valence::custom_payload::CustomPayloadPlugin,
            valence::op_level::OpLevelPlugin,
            valence_network::NetworkPlugin,
        ))
        .add_systems(Startup, setup)
        .add_systems(Update, (init_clients, despawn_disconnected_clients))
        .run();
}

fn setup(
    mut commands: Commands,
    server: Res<Server>,
    dimensions: Res<DimensionTypeRegistry>,
    biomes: Res<BiomeRegistry>,
) {
    let layer = LayerBundle::new(ident!("overworld"), &dimensions, &biomes, &server);

    commands.spawn(layer);
}

fn init_clients(
    mut clients: Query<
        (
            &mut Client,
            &mut Position,
            &mut EntityLayerId,
            &mut VisibleChunkLayer,
            &mut VisibleEntityLayers,
            &mut GameMode,
        ),
        Added<Client>,
    >,
    layers: Query<Entity, (With<ChunkLayer>, With<EntityLayer>)>,
) {
    for (
        mut client,
        mut pos,
        mut layer_id,
        mut visible_chunk_layer,
        mut visible_entity_layers,
        mut game_mode,
    ) in &mut clients
    {
        let layer = layers.single();

        pos.0 = [0.0, f64::from(64) + 1.0, 0.0].into();
        layer_id.0 = layer;
        visible_chunk_layer.0 = layer;
        visible_entity_layers.0.insert(layer);

        *game_mode = GameMode::Spectator;

        client.send_chat_message("It's been a while since anyone has logged in so the main server is down to save money. Please wait (maybe 2-3 minutes) while it starts up again and you will be automatically connected to it...");
    }
}
