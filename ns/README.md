# Updating vocabulary

Vocabulary definitions are managed in context.jsonld. Add or change entries within this file. Regenerate shex.ttl and index.html as described below.

# Building index.html, shex.jsonld and shex.ttl

All files are based on context.jsonld,. Run `mk_vocab.rb` to build both `index.html` and `shex.ttl`. Open index.html, and generate HTML to save over itself to remove ReSpec dependencies.
