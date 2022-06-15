import { render } from '~/lib/gfm';

describe('gfm', () => {
  const markdownToAST = async (markdown) => {
    let result;

    await render({
      markdown,
      renderer: (tree) => {
        result = tree;
      },
    });

    return result;
  };

  const expectInRoot = (result, ...nodes) => {
    expect(result).toEqual(
      expect.objectContaining({
        children: expect.arrayContaining(nodes),
      }),
    );
  };

  describe('render', () => {
    it('processes Commonmark and provides an ast to the renderer function', async () => {
      const result = await markdownToAST('This is text');

      expect(result.type).toBe('root');
    });

    it('transforms raw HTML into individual nodes in the AST', async () => {
      const result = await markdownToAST('<strong>This is bold text</strong>');

      expectInRoot(
        result,
        expect.objectContaining({
          children: expect.arrayContaining([
            expect.objectContaining({
              type: 'element',
              tagName: 'strong',
            }),
          ]),
        }),
      );
    });

    it('returns the result of executing the renderer function', async () => {
      const rendered = { value: 'rendered tree' };

      const result = await render({
        markdown: '<strong>This is bold text</strong>',
        renderer: () => {
          return rendered;
        },
      });

      expect(result).toEqual(rendered);
    });

    it('transforms footnotes into footnotedefinition and footnotereference tags', async () => {
      const result = await markdownToAST(
        `footnote reference [^footnote]

[^footnote]: Footnote definition`,
      );

      expectInRoot(
        result,
        expect.objectContaining({
          children: expect.arrayContaining([
            expect.objectContaining({
              type: 'element',
              tagName: 'footnotereference',
              properties: {
                identifier: 'footnote',
                label: 'footnote',
              },
            }),
          ]),
        }),
      );

      expectInRoot(
        result,
        expect.objectContaining({
          tagName: 'footnotedefinition',
          properties: {
            identifier: 'footnote',
            label: 'footnote',
          },
        }),
      );
    });
  });
});
