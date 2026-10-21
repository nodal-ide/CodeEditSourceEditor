import Foundation

enum HighlightingFixtures {
    enum Thresholds {
        static let visibleChunkLength = 4000
        static let maxVisibleLayers = 20
        static let maxVisibleIntersections = 400
        static let maxInjectionQueriesPerEdit = 4
        static let scrollOffsets = [0.0, 0.25, 0.5, 0.75, 0.99]
    }

    static let purePHP = """
    <?php

    declare(strict_types=1);

    final class Greeter
    {
        public function greet(string $name): string
        {
            return "Hello, {$name}!";
        }
    }

    $greeter = new Greeter();
    echo $greeter->greet('CodeEdit');
    """

    static let mixedPHPHTML = """
    <!doctype html>
    <html lang="en">
    <head>
        <title><?php echo $title; ?></title>
        <style>
            .card { color: #333; }
        </style>
    </head>
    <body>
        <header>
            <h1><?= htmlspecialchars($title) ?></h1>
        </header>
        <main>
            <div class="card">
                <?php if ($items): ?>
                    <ul>
                        <?php foreach ($items as $item): ?>
                            <li><?= htmlspecialchars($item) ?></li>
                        <?php endforeach; ?>
                    </ul>
                <?php endif; ?>
            </div>
            <script>
                const title = <?= json_encode($title) ?>;
                console.log(title);
            </script>
        </main>
    </body>
    </html>
    """

    static let multiplePHPHTMLIslands = """
    <?php $title = 'Islands'; ?>
    <section class="one">
        <h2><?= $title ?></h2>
        <p>First HTML island.</p>
    </section>
    <?php foreach ([1, 2, 3] as $value): ?>
        <article class="item-<?= $value ?>">
            <span><?= $value ?></span>
        </article>
    <?php endforeach; ?>
    <footer>
        <p>Last HTML island.</p>
    </footer>
    """

    static let nestedZones = """
    <!doctype html>
    <html>
    <head>
        <style>
            .grid { display: grid; }
            .grid > .item { padding: 1rem; }
        </style>
    </head>
    <body>
        <div class="grid">
            <script type="module">
                import { render } from './render.js';
                render(document.querySelector('.grid'));
            </script>
            <div class="item">
                <?php if ($visible): ?>
                    <strong><?= $label ?></strong>
                <?php endif; ?>
            </div>
        </div>
    </body>
    </html>
    """

    static let multipleMarkdownInlineIslands = """
    # Inline Islands

    **bold one**

    Text with `inline code`.

    **bold two**

    - list item with **bold three**
    - list item with `code four`

    [link](https://example.com)
    """

    static let largeComponentFile = """
    <script lang="ts">
        export let title: string;
        export let items: string[] = [];
    </script>

    <main>
        <h1>{title}</h1>
        {#each items as item}
            <article class="item">
                <h2>{item}</h2>
                <p>Component content for {item}.</p>
            </article>
        {/each}
    </main>

    <style>
        main { display: grid; gap: 1rem; }
        .item { padding: 1rem; }
    </style>
    """

    static func largeMixedPHP(islandCount: Int = 300) -> String {
        let prose = String(
            repeating: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. ",
            count: 55
        )
        var output = "<!doctype html>\n<html>\n<body>\n"

        for index in 0..<islandCount {
            output += """
            <section class="card-\(index)">
                <h2>Card \(index)</h2>
                <p>\(prose)</p>
                <?php echo $items[\(index)] ?? 'none'; ?>
                <p><?= htmlspecialchars($items[\(index)] ?? '') ?></p>
                <script>const value\(index) = \(index);</script>
                <style>.card-\(index) { color: red; }</style>
            </section>

            """
        }

        output += "</body>\n</html>\n"
        return output
    }
}
