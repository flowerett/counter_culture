require File.expand_path(File.dirname(__FILE__) + '/spec_helper')

require 'database_cleaner'
DatabaseCleaner.strategy = :deletion

describe "CounterCulture" do
  before(:each) do
    DatabaseCleaner.clean
  end

  it "should fix a simple counter cache correctly" do
    user = User.create
    product = Product.create

    expect(user.reviews_count).to eq 0
    expect(product.reviews_count).to eq 0
    expect(user.review_approvals_count).to eq 0

    review = Review.create :user_id => user.id, :product_id => product.id, :approvals => 69

    user.reload
    product.reload

    expect(user.reviews_count).to eq 1
    expect(product.reviews_count).to eq 1
    expect(user.review_approvals_count).to eq 69

    user.reviews_count = 0
    product.reviews_count = 2
    user.review_approvals_count = 7
    user.save!
    product.save!

    fixed = Review.counter_culture_fix_counts :skip_unsupported => true
    expect(fixed.length).to eq 3

    user.reload
    product.reload

    expect(user.reviews_count).to eq 1
    expect(product.reviews_count).to eq 1
    expect(user.review_approvals_count).to eq 69
  end

  it "should fix where the count should go back to zero correctly" do
    user = User.create
    product = Product.create

    expect(user.reviews_count).to eq 0

    user.reviews_count = -1
    user.save!

    fixed = Review.counter_culture_fix_counts :skip_unsupported => true
    expect(fixed.length).to eq 1

    user.reload

    expect(user.reviews_count).to eq 0

  end

  it "should fix a STI counter cache correctly" do
    company = Company.create
    user = User.create :manages_company_id => company.id
    product = Product.create

    expect(product.twitter_reviews_count).to eq 0

    review = Review.create :user_id => user.id, :product_id => product.id, :approvals => 42
    twitter_review = TwitterReview.create :user_id => user.id, :product_id => product.id, :approvals => 32

    company.reload
    user.reload
    product.reload

    expect(product.twitter_reviews_count).to eq 1

    product.twitter_reviews_count = 2
    product.save!

    TwitterReview.counter_culture_fix_counts

    product.reload

    expect(product.twitter_reviews_count).to eq 1
  end

  it "should fix a second-level counter cache correctly" do
    company = Company.create
    user = User.create :manages_company_id => company.id
    product = Product.create

    expect(company.reviews_count).to eq 0
    expect(user.reviews_count).to eq 0
    expect(product.reviews_count).to eq 0
    expect(company.review_approvals_count).to eq 0

    review = Review.create :user_id => user.id, :product_id => product.id, :approvals => 42

    company.reload
    user.reload
    product.reload

    expect(company.reviews_count).to eq 1
    expect(user.reviews_count).to eq 1
    expect(product.reviews_count).to eq 1
    expect(company.review_approvals_count).to eq 42

    company.reviews_count = 2
    company.review_approvals_count = 7
    user.reviews_count = 3
    product.reviews_count = 4
    company.save!
    user.save!
    product.save!

    Review.counter_culture_fix_counts :skip_unsupported => true
    company.reload
    user.reload
    product.reload

    expect(company.reviews_count).to eq 1
    expect(user.reviews_count).to eq 1
    expect(product.reviews_count).to eq 1
    expect(company.review_approvals_count).to eq 42
  end

  it "should fix a custom counter cache correctly" do
    user = User.create
    product = Product.create

    expect(product.rexiews_count).to eq 0

    review = Review.create :user_id => user.id, :product_id => product.id

    product.reload

    expect(product.rexiews_count).to eq 1

    product.rexiews_count = 2
    product.save!

    Review.counter_culture_fix_counts :skip_unsupported => true

    product.reload
    expect(product.rexiews_count).to eq 1
  end

  it "should fix a dynamic counter cache correctly" do
    user = User.create
    product = Product.create

    expect(user.using_count).to eq 0
    expect(user.tried_count).to eq 0

    review_using = Review.create :user_id => user.id, :product_id => product.id, :review_type => 'using'

    user.reload

    expect(user.using_count).to eq 1
    expect(user.tried_count).to eq 0

    review_tried = Review.create :user_id => user.id, :product_id => product.id, :review_type => 'tried'

    user.reload

    expect(user.using_count).to eq 1
    expect(user.tried_count).to eq 1

    user.using_count = 2
    user.tried_count = 3
    user.save!

    Review.counter_culture_fix_counts :skip_unsupported => true

    user.reload

    expect(user.using_count).to eq 1
    expect(user.tried_count).to eq 1
  end

  it "should fix a string counter cache correctly" do
    string_id = HasStringId.create({:id => "bbb"})

    user = User.create :has_string_id_id => string_id.id

    string_id.reload
    expect(string_id.users_count).to eq 1

    user2 = User.create :has_string_id_id => string_id.id

    string_id.reload
    expect(string_id.users_count).to eq 2

    string_id.users_count = 123
    string_id.save!

    string_id.reload
    expect(string_id.users_count).to eq 123

    User.counter_culture_fix_counts

    string_id.reload
    expect(string_id.users_count).to eq 2
  end

  it "should correctly fix float values that came out of sync" do
    user = User.create

    r1 = Review.create :user_id => user.id, :value => 3.4
    r2 = Review.create :user_id => user.id, :value => 7.2
    r3 = Review.create :user_id => user.id, :value => 5

    user.update_column(:review_value_sum, 0)
    Review.counter_culture_fix_counts skip_unsupported: true

    user.reload
    expect(user.review_value_sum.round(1)).to eq 15.6

    r2.destroy

    user.update_column(:review_value_sum, 0)
    Review.counter_culture_fix_counts skip_unsupported: true

    user.reload
    expect(user.review_value_sum.round(1)).to eq 8.4

    r3.destroy

    user.update_column(:review_value_sum, 0)
    Review.counter_culture_fix_counts skip_unsupported: true

    user.reload
    expect(user.review_value_sum.round(1)).to eq 3.4

    r1.destroy

    user.update_column(:review_value_sum, 0)
    Review.counter_culture_fix_counts skip_unsupported: true

    user.reload
    expect(user.review_value_sum.round(1)).to eq 0
  end

  it "should use relation primary key on counter destination table correctly when fixing counts" do
    subcateg = Subcateg.create :subcat_id => Subcateg::SUBCAT_1
    post = Post.new
    post.subcateg = subcateg
    post.save!

    subcateg.posts_count = -1
    subcateg.save!

    fixed = Post.counter_culture_fix_counts :only => :subcateg

    expect(fixed.length).to eq 1
    expect(subcateg.reload.posts_count).to eq 1
  end

  it "should use primary key on counted records table correctly when fixing counts" do
    subcateg = Subcateg.create :subcat_id => Subcateg::SUBCAT_1
    post = Post.new
    post.subcateg = subcateg
    post.save!

    post_comment = PostComment.create!(:post_id => post.id)

    post.comments_count = -1
    post.save!

    fixed = PostComment.counter_culture_fix_counts
    expect(fixed.length).to eq 1
    expect(post.reload.comments_count).to eq 1
  end


  it "should use multi-level relation primary key on counter destination table correctly when fixing counts" do
    categ = Categ.create :cat_id => Categ::CAT_1
    subcateg = Subcateg.new :subcat_id => Subcateg::SUBCAT_1
    subcateg.categ = categ
    subcateg.save!

    post = Post.new
    post.subcateg = subcateg
    post.save!

    categ.posts_count = -1
    categ.save!

    fixed = Post.counter_culture_fix_counts :only => [[:subcateg, :categ]]

    expect(fixed.length).to eq 1
    expect(categ.reload.posts_count).to eq 1
  end

  it "should correctly fix the counter caches for thousands of records when counter is conditional" do
    # first, clean up
    ConditionalDependent.delete_all
    ConditionalMain.delete_all

    1000.times do |i|
      main = ConditionalMain.create
      3.times { main.conditional_dependents.create(:condition => main.id % 2 == 0) }
    end

    ConditionalMain.find_each { |main| expect(main.conditional_dependents_count).to eq(main.id % 2 == 0 ? 3 : 0) }

    ConditionalMain.order('random()').limit(50).update_all :conditional_dependents_count => 1
    ConditionalDependent.counter_culture_fix_counts :batch_size => 100

    ConditionalMain.find_each { |main| expect(main.conditional_dependents_count).to eq(main.id % 2 == 0 ? 3 : 0) }
  end

  it "should correctly fix the counter caches when no dependent record exists for some of main records" do
    # first, clean up
    SimpleDependent.delete_all
    SimpleMain.delete_all

    1000.times do |i|
      main = SimpleMain.create
      (main.id % 4).times { main.simple_dependents.create }
    end

    SimpleMain.find_each { |main| expect(main.simple_dependents_count).to eq main.id % 4 }

    SimpleMain.order('random()').limit(50).update_all simple_dependents_count: 1
    SimpleDependent.counter_culture_fix_counts :batch_size => 100

    SimpleMain.find_each { |main| expect(main.simple_dependents_count).to eq main.id % 4 }
  end

  it "should correctly fix the counter caches with thousands of records" do
    # first, clean up
    SimpleDependent.delete_all
    SimpleMain.delete_all

    1000.times do |i|
      main = SimpleMain.create
      3.times { main.simple_dependents.create }
    end

    SimpleMain.find_each { |main| expect(main.simple_dependents_count).to eq 3 }

    SimpleMain.order('random()').limit(50).update_all simple_dependents_count: 1
    SimpleDependent.counter_culture_fix_counts :batch_size => 100

    SimpleMain.find_each { |main| expect(main.simple_dependents_count).to eq 3 }
  end

  it "should raise a good error message when calling fix_counts with no caches defined" do
    expect { Category.counter_culture_fix_counts }.to raise_error "No counter cache defined on Category"
  end

  describe 'self referemtial counter cache' do
    it "fixes counter cache" do
      company = Company.create!
      company.children << Company.create!

      company.children_count = -1
      company.save!

      fixed = Company.counter_culture_fix_counts
      expect(fixed.length).to eq 1
      expect(company.reload.children_count).to eq 1
    end
  end

  it 'should fix polymorphic assosiations' do
    user = User.create
    image = Image.create :owner => user

    user.images_count = 12
    user.save!
    fixed = Image.counter_culture_fix_counts

    expect(fixed.length).to eq 1
    expect(user.reload.images_count).to eq 1
  end
end