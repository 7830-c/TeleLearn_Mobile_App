import '../models/course_model.dart';

class DefaultCoursesData {
  static List<CourseModel> getInitialCourses() {
    return [
      CourseModel(
        id: '1',
        channelId: 1001928472918,
        title: 'Mastering Flutter & Mobile Architecture',
        description: 'Complete end-to-end masterclass on Flutter, Riverpod, clean architecture, SQLite caching, and YouTube-like custom video players.',
        modules: [
          CourseModule(
            id: 101,
            title: 'Module 1: High-Performance Architecture & State',
            lessons: [
              CourseLesson(
                id: 1001,
                title: '01. Architecture Foundations & Offline SQLite Engines',
                duration: 1420, // 23 mins 40 secs
                size: 48 * 1024 * 1024,
                mimeType: 'video/mp4',
                videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4',
                thumbnailUrl: 'https://images.unsplash.com/photo-1517694712202-14dd9538aa97?w=600&q=80',
                summary: 'Comprehensive breakdown of building zero-backend offline first Flutter applications with SQLite synchronization.',
              ),
              CourseLesson(
                id: 1002,
                title: '02. Reactive Providers & SWR Caching Strategies',
                duration: 1780, // 29 mins 40 secs
                size: 62 * 1024 * 1024,
                mimeType: 'video/mp4',
                videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4',
                thumbnailUrl: 'https://images.unsplash.com/photo-1526374965328-7f61d4dc18c5?w=600&q=80',
                summary: 'Implementing Stale-While-Revalidate caching patterns for instantaneous UI updates and background refreshes.',
              ),
              CourseLesson(
                id: 1003,
                title: '03. Custom Canvas & Micro-Animations in Flutter',
                duration: 1250, // 20 mins 50 secs
                size: 39 * 1024 * 1024,
                mimeType: 'video/mp4',
                videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4',
                thumbnailUrl: 'https://images.unsplash.com/photo-1555066931-4365d14bab8c?w=600&q=80',
                summary: 'Building custom painters, glow effects, ripple waves, and fluid gestures.',
              ),
            ],
            notes: [
              CourseNote(
                id: 501,
                title: 'Architecture Blueprint & Layer Isolation.pdf',
                fileName: 'Flutter_Clean_Architecture_Guide.pdf',
                size: 4 * 1024 * 1024,
                text: 'Key architectural rules: Repositories must never depend on UI providers. SQLite is single source of truth.',
              ),
              CourseNote(
                id: 502,
                title: 'SQLite Schemas and Indexing Rules.pdf',
                fileName: 'Database_Optimization_CheatSheet.pdf',
                size: 2 * 1024 * 1024,
                text: 'Index lesson_id, course_id, and last_watched_at for sub-millisecond query execution.',
              ),
            ],
          ),
          CourseModule(
            id: 102,
            title: 'Module 2: YouTube-Style Streaming & Gesture Engine',
            lessons: [
              CourseLesson(
                id: 1004,
                title: '04. Building Custom Video Scrubbers & Dynamic Buffering',
                duration: 2100, // 35 mins
                size: 78 * 1024 * 1024,
                mimeType: 'video/mp4',
                videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4',
                thumbnailUrl: 'https://images.unsplash.com/photo-1574717024653-61fd2cf4d44d?w=600&q=80',
                summary: 'Engineering custom scrubber sliders, double-tap seek bubbles (+10s / -10s), and hold-to-speed-up gestures.',
              ),
              CourseLesson(
                id: 1005,
                title: '05. Local HTTP Range Proxy & Packet Pre-buffering',
                duration: 1890, // 31 mins 30 secs
                size: 69 * 1024 * 1024,
                mimeType: 'video/mp4',
                videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4',
                thumbnailUrl: 'https://images.unsplash.com/photo-1536240478700-b869070f9279?w=600&q=80',
                summary: 'Running an in-memory embedded Dart server to serve 206 Partial Content streams directly to media players.',
              ),
            ],
            notes: [
              CourseNote(
                id: 503,
                title: 'Video Gesture Mathematics & Physics.pdf',
                fileName: 'Gesture_Physics_Calculations.pdf',
                size: 3 * 1024 * 1024,
                text: 'Calculating velocity and delta offsets for volume, brightness, and horizontal frame seeking.',
              ),
            ],
          ),
        ],
      ),
      CourseModel(
        id: '2',
        channelId: 1001883920192,
        title: 'System Design & Distributed Systems Mastery',
        description: 'Large-scale system design, caching topologies, distributed message queues, consistent hashing, and database sharding.',
        modules: [
          CourseModule(
            id: 201,
            title: 'Module 1: Core Building Blocks & Caching Layers',
            lessons: [
              CourseLesson(
                id: 2001,
                title: '01. Consistent Hashing & Distributed Key-Value Stores',
                duration: 1650,
                size: 54 * 1024 * 1024,
                mimeType: 'video/mp4',
                videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyBlazes.mp4',
                thumbnailUrl: 'https://images.unsplash.com/photo-1558494949-ef010cbdcc31?w=600&q=80',
                summary: 'How virtual nodes prevent hot-spotting in distributed hash rings.',
              ),
              CourseLesson(
                id: 2002,
                title: '02. Rate Limiting Algorithms (Token Bucket & Leaky Bucket)',
                duration: 1320,
                size: 42 * 1024 * 1024,
                mimeType: 'video/mp4',
                videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4',
                thumbnailUrl: 'https://images.unsplash.com/photo-1451187580459-43490279c0fa?w=600&q=80',
                summary: 'Implementing high-throughput distributed rate limiters using Redis sliding window logs.',
              ),
            ],
            notes: [
              CourseNote(
                id: 504,
                title: 'Distributed Systems Interview Cheatsheet.pdf',
                fileName: 'System_Design_Cheatsheet.pdf',
                size: 5 * 1024 * 1024,
                text: 'Latency numbers every programmer should know. Memory vs SSD vs Disk vs Network round-trip times.',
              ),
            ],
          ),
          CourseModule(
            id: 202,
            title: 'Module 2: Video Streaming Architecture & CDNs',
            lessons: [
              CourseLesson(
                id: 2003,
                title: '03. HLS, DASH & HTTP Range Request Protocols',
                duration: 2280,
                size: 85 * 1024 * 1024,
                mimeType: 'video/mp4',
                videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/Sintel.mp4',
                thumbnailUrl: 'https://images.unsplash.com/photo-1518770660439-4636190af475?w=600&q=80',
                summary: 'Deep dive into adaptive bitrate streaming, video segmentation, and CDN edge caching.',
              ),
            ],
            notes: [],
          ),
        ],
      ),
      CourseModel(
        id: '3',
        channelId: 1001774829103,
        title: 'Fullstack Next.js & Modern Backend Systems',
        description: 'Building modern full-stack web applications with Next.js 15, Server Actions, PostgreSQL, and real-time WebSockets.',
        modules: [
          CourseModule(
            id: 301,
            title: 'Module 1: Server Components & Edge Computing',
            lessons: [
              CourseLesson(
                id: 3001,
                title: '01. React Server Components and Streaming SSR',
                duration: 1540,
                size: 50 * 1024 * 1024,
                mimeType: 'video/mp4',
                videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/SubaruOutbackSeeTheWorld.mp4',
                thumbnailUrl: 'https://images.unsplash.com/photo-1555066931-4365d14bab8c?w=600&q=80',
                summary: 'How React Server Components eliminate client bundle sizes and optimize TTFB.',
              ),
              CourseLesson(
                id: 3002,
                title: '02. Database Indexing & Connection Pooling',
                duration: 1410,
                size: 47 * 1024 * 1024,
                mimeType: 'video/mp4',
                videoUrl: 'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4',
                thumbnailUrl: 'https://images.unsplash.com/photo-1504639725590-34d0984388bd?w=600&q=80',
                summary: 'PostgreSQL execution plans, b-tree indexes, and PgBouncer connection multiplexing.',
              ),
            ],
            notes: [
              CourseNote(
                id: 505,
                title: 'SQL Performance & Indexing Guide.pdf',
                fileName: 'Postgres_Performance_Optimization.pdf',
                size: 3 * 1024 * 1024,
                text: 'Understanding EXPLAIN ANALYZE, sequential scans vs index scans.',
              ),
            ],
          ),
        ],
      ),
    ];
  }
}
